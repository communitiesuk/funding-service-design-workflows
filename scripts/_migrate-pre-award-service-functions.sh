#!/bin/bash

SERVICE_NAME_FUND_STORE='fsd-fund-store'
SERVICE_NAME_APPLICATION_STORE='fsd-application-store'
SERVICE_NAME_ASSESSMENT_STORE='fsd-assessment-store'
AWS_COPILOT_TAG_NAME="copilot-service"
AWS_CLOUDFORMATION_TAG_NAME="aws:cloudformation:logical-id"
AWS_PREAWARD_RDS_TAG_VALUE="fsdpreawardstoresclusterAuroraSecret"
AWS_SSM_BASTION_PIDS=''

function _get_secret_value() {
  local secret_tag_name="$1"
  local secret_tag_value="$2"

  local secret_arn=$(aws secretsmanager list-secrets --query "SecretList[?Tags[?Key=='${secret_tag_name}' && Value=='${secret_tag_value}']].ARN" | jq -r '.[0]')

  aws secretsmanager get-secret-value --secret-id $secret_arn --query 'SecretString' --output 'text'
}

# Retrieve credentials for a service-level DB and setup a bastion connection for it.
function _get_db_uri_from_secret_value() {
  local username=$(echo "$1" | jq -r '.username')
  local password=$(echo "$1" | jq -r '.password')
  local dbname=$(echo "$1" | jq -r '.dbname')
  local port=$2

  echo "postgresql://${username}:${password}@localhost:${port}/${dbname}"
}

function _build_db_uri_via_bastion() {
  local secret_tag_name="$1"
  local secret_tag_value="$2"
  local bastion_port="$3"

  local db_credentials=$(_get_secret_value "${secret_tag_name}" "${secret_tag_value}")
  local host=$(echo "$db_credentials" | jq -r '.host')
  local port=$(echo "$db_credentials" | jq -r '.port')

  _get_db_uri_from_secret_value ${db_credentials} ${bastion_port}
}

function _kill_bastions() {
  for ppid in ${AWS_SSM_BASTION_PIDS}; do
    echoerr "--> Terminating bastion tunnel with pid=${ppid}\n"

    # Get all child processes of the parent
    local child_pids=$(pgrep -P "$ppid")

    # Terminate child processes
    for cpid in $child_pids; do
      kill "$cpid"
    done

    kill "$ppid"
  done

  # Wait, then flush stdout, so that output from processes terminating is displayed here.
  sleep 1
  echo ''

  AWS_SSM_BASTION_PIDS=""
}

function _start_bastion_session() {
  local secret_tag_name="$1"
  local secret_tag_value="$2"
  local bastion_port="$3"

  local db_credentials=$(_get_secret_value "${secret_tag_name}" "${secret_tag_value}")
  local remote_host=$(echo "$db_credentials" | jq -r '.host')
  local remote_port=$(echo "$db_credentials" | jq -r '.port')

  local bastion_id=$(aws ec2 describe-instances --filters Name=tag:Name,Values=\'*-bastion\' "Name=instance-state-name,Values='running'" --query "Reservations[*].Instances[*].InstanceId" | jq -r '.[0][0]')

  aws ssm start-session --target $bastion_id --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters host="$remote_host",portNumber="$remote_port",localPortNumber="$bastion_port" >/dev/null 2>/dev/null &

  local bastion_pid=$!
  AWS_SSM_BASTION_PIDS="${AWS_SSM_BASTION_PIDS} ${bastion_pid}"

  trap _kill_bastions EXIT
}

function _get_table_stats() {
  DB_URI="$1"
  EXPORT_FILENAME="$2"

  PSQL_TABLE_STATS_QUERY=$(
    cat <<EOF
DO \$\$
DECLARE
    tbl RECORD;
BEGIN
    -- Create a temporary table for combined results
    CREATE TEMP TABLE combined_results (table_name text, row_count int, table_size text, hash bigint);

    FOR tbl IN
        SELECT table_name
        FROM information_schema.tables
        WHERE table_schema = 'public'
        AND table_type = 'BASE TABLE'
        AND table_name != 'alembic_version'
    LOOP
    EXECUTE format('INSERT INTO combined_results SELECT %L, count(1), pg_size_pretty(pg_total_relation_size(%L)), coalesce(sum(hashtext(t::text)), 0) FROM %I.%I as t', tbl.table_name, tbl.table_name, 'public', tbl.table_name);
    END LOOP;
END \$\$;
EOF
  )

  # Run the query and print to stdout
  psql ${DB_URI} <<EOF
${PSQL_TABLE_STATS_QUERY};

SELECT * FROM combined_results ORDER BY table_name ASC;
EOF

  # Run the query with non-deterministic size column excluded, and export to file for later diffing.
  psql ${DB_URI} <<EOF >${EXPORT_FILENAME}
${PSQL_TABLE_STATS_QUERY};

SELECT table_name, row_count, hash FROM combined_results ORDER BY table_name ASC;
EOF
}

function _validate_target_db_is_safe_to_migrate() {
  local source_db_uri="$1"
  local target_db_uri="$2"

  echoerr "--> Checking target DB is in a safe state to receive data ... "

  local source_db_tables=$(
    psql "$source_db_uri" <<EOF
COPY (
  SELECT string_agg(' ', table_name)
  FROM information_schema.tables
  WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE'
  AND table_name != 'alembic_version'
) TO STDOUT;
EOF
  )

  local status='ok'
  for tbl in ${source_db_tables}; do
    local result=$(psql "$target_db_uri" -c "COPY (SELECT coalesce(COUNT(*)::text, 'null') FROM ${tbl}) TO STDOUT")
    if [ "${result}" != "0" ]; then
      if [ "${status}" == "ok" ]; then
        echoerr 'done\n\n'
        echoerr '--> ERROR: Some tables to be migrated already contain data in the target DB:\n'
      fi

      echoerr "--> * Table \`${tbl}\` has ${result} rows (it should be empty)\n"
      status="error"
    fi
  done

  if [ "${status}" == "ok" ]; then
    echoerr "done\n"
  else
    echoerr "\n"
  fi

  echo ${status}
}

function _bail_if_not_aws_cloudshell() {
  if [ "$AWS_EXECUTION_ENV" != "CloudShell" ]; then
    echoerr "WARNING: This script should not be run locally against RDS Databases. Open AWS Console and use CloudShell instead.\n"
    exit 1
  fi
}

function echoerr() {
  echo -en "$1" >&2
}

function _prompt_for_input() {
  local prompt_text="$1"

  while true; do
    read -p "${prompt_text} [Y(es) / N(o)]: " selection >&2
    echoerr "\n"

    local clean_selection=$(echo ${selection} | tr '[:lower:]' '[:upper:]')
    case ${clean_selection} in
    Y | YES)
      return 0
      ;;
    N | NO)
      echoerr "--> WARNING: This step has been SKIPPED.\n"
      echoerr "--> WARNING: This step has been SKIPPED.\n"
      echoerr "--> WARNING: This step has been SKIPPED.\n\n"
      return 1
      ;;
    *) ;;
    esac
  done
}

function maybe_run_section() {
  local section_name="$1"
  local manually_confirm_step=$2

  local line_width=80
  local stars=$(printf "%-${line_width}s" "" | tr " " "*")
  local padded_section=$(printf "%*s" $(((${#section_name} + line_width) / 2)) "$section_name")
  local centered_section=$(printf "%-${line_width}s" "$padded_section")

  echo -e "\n${stars}\n${centered_section}\n${stars}" >&2

  if $manually_confirm_step; then
    (_prompt_for_input "Run this step?" && echo "yes") || echo "no"
  else
    echo "yes"
  fi
}

function print_subsection_header() {
  local subsection_name="$1"
  local line_width=80
  local content=" $subsection_name "
  local content_length=${#content}
  local padding=$((line_width - content_length))
  local left_padding=$((padding / 2))
  local right_padding=$((padding - left_padding))

  echo "" >&2
  printf "%0.s=" $(seq 1 "$left_padding") >&2
  printf "$content" >&2
  printf "%0.s=" $(seq 1 "$right_padding") >&2
  echo "" >&2
}

function watch_for_ecs_service_deployment_completion() {
  local cluster_id="$1"
  local service_id="$2"

  echoerr "--> Waiting for ${service_id} ..."
  local status=$(
    aws ecs describe-services \
      --cluster "${cluster_id}" \
      --services "${service_id}" \
      --query "length(services[?!(length(deployments) == \`1\` && runningCount == desiredCount)]) == \`0\`" \
      --output text
  )

  while [ "$status" != "True" ]; do
    echoerr '.'
    sleep 5
    local status=$(
      aws ecs describe-services \
        --cluster "${cluster_id}" \
        --services "${service_id}" \
        --query "length(services[?!(length(deployments) == \`1\` && runningCount == desiredCount)]) == \`0\`" \
        --output text
    )
  done

  echoerr ' stable\n'
}

function set_maintenance_mode() {
  local maintenance_mode="$1"
  local aws_environment="$2"

  echoerr "--> Setting FSD_FRONTEND_MAINTENANCE_MODE config to '${maintenance_mode}'\n"
  aws ssm put-parameter --name "/copilot/pre-award/${aws_environment}/secrets/FSD_FRONTEND_MAINTENANCE_MODE" --value "${maintenance_mode}" --type "SecureString" --overwrite >/dev/null

  echoerr "--> Setting FSD_ASSESSMENT_MAINTENANCE_MODE config to '${maintenance_mode}'\n"
  aws ssm put-parameter --name "/copilot/pre-award/${aws_environment}/secrets/FSD_ASSESSMENT_MAINTENANCE_MODE" --value "${maintenance_mode}" --type "SecureString" --overwrite >/dev/null

  local cluster_id=$(_ecs_cluster_id)
  local frontend_svc_id=$(_ecs_service_id "${cluster_id}" "fsd-frontend")
  local assessment_svc_id=$(_ecs_service_id "${cluster_id}" "fsd-assessment")

  print_subsection_header "Re-deploying services"
  echoerr "--> Triggering a re-deployment for ${frontend_svc_id}\n"
  aws ecs update-service --cluster ${cluster_id} --service ${frontend_svc_id} --force-new-deployment >/dev/null
  echoerr "--> Triggering a re-deployment for ${assessment_svc_id}\n"
  aws ecs update-service --cluster ${cluster_id} --service ${assessment_svc_id} --force-new-deployment >/dev/null

  print_subsection_header "Waiting for deployments to stabilise"
  watch_for_ecs_service_deployment_completion "${cluster_id}" "${frontend_svc_id}"
  watch_for_ecs_service_deployment_completion "${cluster_id}" "${assessment_svc_id}"
}

function _ecs_cluster_id() {
  echoerr "--> Retrieving ECS pre-award Cluster ID: "
  local cluster_id=$(aws ecs list-clusters --query "clusterArns[?contains(@, 'pre-award-')]" --output text | sed 's|.*/||')
  echoerr "${cluster_id}\n"

  echo "${cluster_id}"
}

function _ecs_service_id() {
  local cluster_id="$1"
  local service_name="$2"

  echoerr "--> Retrieving ECS Service ID for ${service_name}: "
  local service_id=$(aws ecs list-services --cluster $cluster_id --query "serviceArns[?contains(@, '-${service_name}-Service')]" --output text | sed 's|.*/||')
  echoerr "${service_id}\n"

  echo ${service_id}
}

function scale_service_instances() {
  local app_name="$1"
  local num_instances="$2"

  local cluster_id=$(aws ecs list-clusters --query "clusterArns[?contains(@, 'pre-award-')]" --output text | sed 's|.*/||')
  local service_id=$(aws ecs list-services --cluster $cluster_id --query "serviceArns[?contains(@, '-${app_name}-Service')]" --output text | sed 's|.*/||')

  echoerr "--> Scaling ${service_id} to ${num_instances} instance(s) ... "
  aws ecs update-service --cluster ${cluster_id} --service ${service_id} --desired-count "${num_instances}" >/dev/null
  echoerr "done\n"

  watch_for_ecs_service_deployment_completion "${cluster_id}" "${service_id}"
}

function migrate_environment_variables_for_service() {
  local app_name="$1"
  local aws_environment="$2"

  # TODO: Add cases for application-store/assessment-store here.
  case "${app_name}" in
  ${SERVICE_NAME_FUND_STORE})
    local env_var_name="FUND_STORE_API_HOST"
    local env_var_value="http://fsd-pre-award-stores:8080/fund"
    local calling_services="fsd-frontend fsd-assessment fsd-assessment-store fsd-application-store fsd-authenticator fsd-fund-application-builder"
    ;;
  *)
    echo "Unknown service name: ${app_name}"
    exit 1
    ;;
  esac

  echoerr "--> Setting ${env_var_name} to ${env_var_value}\n"
  aws ssm put-parameter --name "/copilot/pre-award/${aws_environment}/secrets/${env_var_name}" --value "${env_var_value}" --type "SecureString" --overwrite >/dev/null

  print_subsection_header "Re-deploying services"
  local cluster_id=$(_ecs_cluster_id)
  for service in ${calling_services}; do
    local service_id=$(_ecs_service_id "${cluster_id}" "${service}")
    echoerr "--> Triggering a re-deployment for ${service_id} ... "
    aws ecs update-service --cluster ${cluster_id} --service ${service_id} --force-new-deployment >/dev/null
    echoerr "done\n"
  done

  print_subsection_header "Waiting for deployments to stabilise"
  for service in ${calling_services}; do
    local service_id=$(_ecs_service_id "${cluster_id}" "${service}")

    watch_for_ecs_service_deployment_completion "${cluster_id}" "${service_id}"
  done
  echoerr "--> Deployments stabilised.\n"
}

function run_pre_flight_checks() {
  local source_app="$1"

  echoerr "--> Resolving source DB credential and opening bastion tunnel ... "
  local source_uri=$(_build_db_uri_via_bastion "${AWS_COPILOT_TAG_NAME}" "${source_app}" 15432)
  _start_bastion_session "${AWS_COPILOT_TAG_NAME}" "${source_app}" 15432
  echoerr "done\n"

  echoerr "--> Resolving target DB credential and opening bastion tunnel ... "
  local target_uri=$(_build_db_uri_via_bastion "${AWS_CLOUDFORMATION_TAG_NAME}" "${AWS_PREAWARD_RDS_TAG_VALUE}" 15433)
  _start_bastion_session "${AWS_CLOUDFORMATION_TAG_NAME}" "${AWS_PREAWARD_RDS_TAG_VALUE}" 15433
  echoerr "done\n"

  echoerr "--> Waiting for bastion tunnels to stabilise ... "
  sleep 5
  echoerr "done\n"

  local result=$(_validate_target_db_is_safe_to_migrate "${source_uri}" "${target_uri}")

  _kill_bastions

  if [ "${result}" != "ok" ]; then
    return 1
  fi
}

function run_pre_award_db_migration() {
  local source_app="$1"

  echoerr "--> Resolving source DB credential and opening bastion tunnel ... "
  local source_uri=$(_build_db_uri_via_bastion "${AWS_COPILOT_TAG_NAME}" "${source_app}" 15432)
  _start_bastion_session "${AWS_COPILOT_TAG_NAME}" "${source_app}" 15432
  echoerr "done\n"

  echoerr "--> Resolving target DB credential and opening bastion tunnel ... "
  local target_uri=$(_build_db_uri_via_bastion "${AWS_CLOUDFORMATION_TAG_NAME}" "${AWS_PREAWARD_RDS_TAG_VALUE}" 15433)
  _start_bastion_session "${AWS_CLOUDFORMATION_TAG_NAME}" "${AWS_PREAWARD_RDS_TAG_VALUE}" 15433
  echoerr "done\n"

  echoerr "--> Waiting for bastion tunnels to stabilise ... "
  sleep 5
  echoerr "done\n"

  print_subsection_header "Analysing source DB state (pre-migrate)"
  _get_table_stats "${source_uri}" "pre_migrate_source_db_stats.txt"
  echoerr "--> Done.\n"

  print_subsection_header "Analysing target DB state (pre-migrate)"
  _get_table_stats "${target_uri}" "pre_migrate_target_db_stats.txt"
  echoerr "--> Done.\n\n\n"

  local result=$(_prompt_for_input "Go ahead with migrating data?" && echo "yes" || echo "no")
  [ "${result}" == "yes" ] || return 0

  print_subsection_header "Doing dump and restore"
  pg_dump --verbose --data-only --format custom --exclude-table alembic_version $source_uri 2>/dev/null | pg_restore --verbose --data-only --format custom --dbname $target_uri || true
  psql ${target_uri} -c "ANALYZE;"

  print_subsection_header "Analysing target DB state (post-migrate) ..."
  _get_table_stats "${target_uri}" "post_migrate_target_db_stats.txt"
  echoerr "--> Done.\n"

  _kill_bastions

  set +e # Don't exit the script if the diff comes back with something.
  diff --side-by-side "pre_migrate_source_db_stats.txt" "post_migrate_target_db_stats.txt" >pre_and_post_diff.txt

  if [ "$?" -eq 0 ]; then
    maybe_run_section "Database migration SUCCESSFUL" false
  else
    maybe_run_section "Database migration FAILED" false
    cat pre_and_post_diff.txt
  fi
}
