#!/bin/bash

SERVICE_NAME_FUND_STORE='fsd-fund-store'
SERVICE_NAME_APPLICATION_STORE='fsd-application-store'
SERVICE_NAME_ASSESSMENT_STORE='fsd-assessment-store'
SERVICE_NAME_ACCOUNT_STORE='fsd-account-store'
AWS_COPILOT_TAG_NAME="copilot-service"
AWS_CLOUDFORMATION_TAG_NAME="aws:cloudformation:logical-id"
AWS_PREAWARD_RDS_TAG_VALUE="fsdpreawardstoresclusterAuroraSecret"
AWS_SSM_BASTION_PIDS=''

function echoerr() {
  # A helper function to print a message to stderr, so that we can use stdout for passing information between
  # function calls. The functions in this script heavily make use of stdout for passing data back and forth, rather than
  # using global variables, so anything that should be shown to the user should be printed on stderr using this function
  # instead.

  echo -en "$1" >&2
}

function _get_secret_value() {
  # Retrieve the value of a secret from AWS SecretsManager
  #
  # Returns the secret value on stdout.

  local secret_tag_name="$1"
  local secret_tag_value="$2"

  local secret_arn=$(aws secretsmanager list-secrets --query "SecretList[?Tags[?Key=='${secret_tag_name}' && Value=='${secret_tag_value}']].ARN" | jq -r '.[0]')

  aws secretsmanager get-secret-value --secret-id $secret_arn --query 'SecretString' --output 'text'
}

function _build_db_uri_via_bastion() {
  # Build a postgresql URI from a RDS Cluster secret stored in SecretsManager and an override port. The override
  # port is *required*, and is expected to be a port that is later exposed on a bastion SSH tunnel.
  #
  # Returns a postgresql URI on stdout.

  local secret_tag_name="$1"
  local secret_tag_value="$2"
  local bastion_port="$3"

  local db_credentials=$(_get_secret_value "${secret_tag_name}" "${secret_tag_value}")
  local host=$(echo "$db_credentials" | jq -r '.host')
  local port=$(echo "$db_credentials" | jq -r '.port')

  local username=$(echo "$db_credentials" | jq -r '.username')
  local password=$(echo "$db_credentials" | jq -r '.password')
  local dbname=$(echo "$db_credentials" | jq -r '.dbname')

  echo "postgresql://${username}:${password}@localhost:${bastion_port}/${dbname}"
}

function _kill_bastions() {
  # Terminate any running bastion tunnels (so that the ports can be reused later, since these functions use fixed port
  # assignments for the source and target DB).
  #
  # No useful return value.

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
  # Open an SSH tunnel using the AWS bastion to the Funding Service VPC so that connections to the databases can be
  # established for migrating data.
  #
  # Sets up a trap so that the bastions are killed when the script exits. Important: this uses the EXIT trap, which
  # triggers when the shell exits. Therefore, this function must not be called in a subshell, otherwise the trap
  # trigger immediately and the bastion tunnels will be killed.
  #
  # No useful return value.

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
  # Collects some audit/safety-check stats on tables in a postgres DB. The stats collected are:
  #  * table name
  #  * number of rows
  #  * approximate size of table on disk (very much not deterministic or exact)
  #  * hash of table contents (row-order insensitive, column-order sensitive)
  #
  # Returns the stats table on stdout.

  local db_uri="$1"
  local export_filename="$2"

  local psql_table_stats_query=$(
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
  psql ${db_uri} <<EOF
${psql_table_stats_query};

SELECT * FROM combined_results ORDER BY table_name ASC;
EOF

  # Run the query with non-deterministic size column excluded, and export to file for later diffing.
  psql ${db_uri} <<EOF >${export_filename}
${psql_table_stats_query};

SELECT table_name, row_count, hash FROM combined_results ORDER BY table_name ASC;
EOF
}

function _validate_target_db_is_safe_to_migrate() {
  # Checks that the target DB's tables are empty and ready to receive data.
  #
  # Returns:
  #   `ok` on stdout if the service migration can go ahead.
  #   `error` on stdout if the target DB contains data and the migration is not safe.

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
  # A naive check that the script is being run in an AWS CloudShell rather than on a local developer machine, so that
  # we aren't pumping data into and out of AWS.
  #
  # Exitcodes:
  #   0 if seemingly running in AWS CloudShell
  #   1 otherwise

  if [ "$AWS_EXECUTION_ENV" != "CloudShell" ]; then
    echoerr "WARNING: This script should not be run locally against RDS Databases. Open AWS Console and use CloudShell instead.\n"
    exit 1
  fi
}

function _prompt_for_input() {
  # Prompt the user for a "Yes" or "No" answer to an arbitrary prompt. Re-prompt if input doesn't match Yes/No.
  #
  # Exitcodes:
  #   0 on a "yes"
  #   1 on a "no"

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
  # Show an h1-style heading, and optionally prompt the user as to whether the section should be executed or not.
  #
  # No useful return value.

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
  # Print an h2-style heading to indicate what's about to happen.
  #
  # No useful return value.

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
  # Monitor an ECS service and wait for any active deployments to finish.
  #
  # No useful return value.

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
  # Toggle pre-award maintenance mode, and re-deploy the two pre-award frontend services so that they pick up
  # the maintenance mode configuration.
  #
  # No useful return value.

  local maintenance_mode="$1"
  local aws_environment="$2"

  echoerr "--> Setting FSD_FRONTEND_MAINTENANCE_MODE config to '${maintenance_mode}'\n"
  aws ssm put-parameter --name "/copilot/pre-award/${aws_environment}/secrets/FSD_FRONTEND_MAINTENANCE_MODE" --value "${maintenance_mode}" --type "SecureString" --overwrite >/dev/null

  echoerr "--> Setting FSD_ASSESSMENT_MAINTENANCE_MODE config to '${maintenance_mode}'\n"
  aws ssm put-parameter --name "/copilot/pre-award/${aws_environment}/secrets/FSD_ASSESSMENT_MAINTENANCE_MODE" --value "${maintenance_mode}" --type "SecureString" --overwrite >/dev/null

  local cluster_id=$(_ecs_cluster_id)
  local frontend_svc_id=$(_ecs_service_id "${cluster_id}" "fsd-pre-award-frontend")

  print_subsection_header "Re-deploying services"
  echoerr "--> Triggering a re-deployment for ${frontend_svc_id}\n"
  aws ecs update-service --cluster ${cluster_id} --service ${frontend_svc_id} --force-new-deployment >/dev/null

  print_subsection_header "Waiting for deployments to stabilise"
  watch_for_ecs_service_deployment_completion "${cluster_id}" "${frontend_svc_id}"
}

function _ecs_cluster_id() {
  # Retrieve the Pre-Award ECS Cluster ID.
  #
  # Returns the cluster ID on stdout.

  echoerr "--> Retrieving ECS pre-award Cluster ID: "
  local cluster_id=$(aws ecs list-clusters --query "clusterArns[?contains(@, 'pre-award-')]" --output text | sed 's|.*/||')
  echoerr "${cluster_id}\n"

  echo "${cluster_id}"
}

function _ecs_service_id() {
  # Retrieve an ECS Service ID
  #
  # Returns the service ID on stdout.

  local cluster_id="$1"
  local service_name="$2"

  echoerr "--> Retrieving ECS Service ID for ${service_name}: "
  local service_id=$(aws ecs list-services --cluster $cluster_id --query "serviceArns[?contains(@, '-${service_name}-Service')]" --output text | sed 's|.*/||')
  echoerr "${service_id}\n"

  echo ${service_id}
}

function scale_service_instances() {
  # Re-deploy an ECS Service so that it has the specified target instance count.
  #
  # No useful return value.

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
  # For a given pre-award store service, update the API host (base URL) used for any apps that call into it.
  #
  # No useful return value.

  local app_name="$1"
  local aws_environment="$2"

  case "${app_name}" in
  ${SERVICE_NAME_FUND_STORE})
    local env_var_name="FUND_STORE_API_HOST"
    local env_var_value="http://fsd-pre-award-stores:8080/fund"
    local calling_services="fsd-frontend fsd-assessment fsd-assessment-store fsd-application-store fsd-authenticator fsd-fund-application-builder"
    ;;
  ${SERVICE_NAME_APPLICATION_STORE})
    local env_var_name="APPLICATION_STORE_API_HOST"
    local env_var_value="http://fsd-pre-award-stores:8080/application"
    local calling_services="fsd-frontend fsd-assessment fsd-assessment-store fsd-fund-application-builder"
    ;;
  ${SERVICE_NAME_ASSESSMENT_STORE})
    local env_var_name="ASSESSMENT_STORE_API_HOST"
    local env_var_value="http://fsd-pre-award-stores:8080/assessment"
    local calling_services="fsd-assessment"
    ;;
  ${SERVICE_NAME_ACCOUNT_STORE})
    local env_var_name="ACCOUNT_STORE_API_HOST"
    local env_var_value="http://fsd-pre-award-stores:8080/account"
    local calling_services="fsd-pre-award-frontend fsd-authenticator"
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
  # Expected to run before any migration actions have happened yet. Runs some checks on the DB to make sure that the
  # target DB is in a reasonable state to receive data (ie the tables exist and are empty).
  #
  # Exitcodes:
  #   0 if the target DB is ready to receive data
  #   1 if the target DB is not safe to migrate

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

function _filter_db_stats() {
  # Filter a db stats file to return a text file showing only the table names that match those in the source db.

  # No useful return value but creates a text file with the filtered output.

  local source_db_tables="$1"
  local file_to_filter="$2"
  local filtered_filename="$3"

  for table_name in $source_db_tables; do
    grep "\b$table_name\b" $file_to_filter | tr "|" "," | tr -d [:blank:] >>${filtered_filename}
  done
}

function run_pre_award_db_migration() {
  # The core logic for migrating data safely from an existing pre-award store, to the new combined pre-award-stores
  # service/database.
  #
  # Exitcodes:
  #   0 on a successful migration
  #   1 on a failed migration

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

  local source_db_tables=$(
    psql "${source_uri}" <<EOF
COPY (
  SELECT string_agg(' ', table_name)
  FROM information_schema.tables
  WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE'
  AND table_name != 'alembic_version'
) TO STDOUT;
EOF
  )

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

  _filter_db_stats "${source_db_tables}" "pre_migrate_source_db_stats.txt" "filtered_pre_migrate_source_db_stats.txt"
  _filter_db_stats "${source_db_tables}" "post_migrate_target_db_stats.txt" "filtered_post_migrate_target_db_stats.txt"

  diff --side-by-side "filtered_pre_migrate_source_db_stats.txt" "filtered_post_migrate_target_db_stats.txt" >pre_and_post_diff.txt

  if [ "$?" -eq 0 ]; then
    maybe_run_section "Database migration SUCCESSFUL" false
  else
    maybe_run_section "Database migration FAILED" false
    cat pre_and_post_diff.txt
    return 1
  fi
}
