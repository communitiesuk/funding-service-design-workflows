#!/bin/bash

set -e  # Exit script if any commands fail

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

  echo $(_get_db_uri_from_secret_value ${db_credentials} ${bastion_port})
}

function _start_bastion_session() {
  local secret_tag_name="$1"
  local secret_tag_value="$2"
  local bastion_port="$3"

  local db_credentials=$(_get_secret_value "${secret_tag_name}" "${secret_tag_value}")
  local remote_host=$(echo "$db_credentials" | jq -r '.host')
  local remote_port=$(echo "$db_credentials" | jq -r '.port')

  local bastion_id=$(aws ec2 describe-instances --filters Name=tag:Name,Values=\'*-bastion\'  "Name=instance-state-name,Values='running'" --query "Reservations[*].Instances[*].InstanceId" | jq -r '.[0][0]')

  aws ssm start-session --target $bastion_id --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters host="$remote_host",portNumber="$remote_port",localPortNumber="$bastion_port" > /dev/null 2> /dev/null &
}

function setup_bastion_for_db_connection_and_get_uri() {
  local source_app="$1"
  local secret_tag_name="$2"
  local secret_tag_value="$3"
  local bastion_port="$4"

  _start_bastion_session "${secret_tag_name}" "${secret_tag_value}" "${bastion_port}"

  echo $(_build_db_uri_via_bastion "${secret_tag_name}" "${secret_tag_value}" "${bastion_port}")
}

function _get_table_stats() {
  DB_URI="$1"
  EXPORT_FILENAME="$2"

  PSQL_TABLE_STATS_QUERY=$(cat <<EOF
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
);

  # Run the query and print to stdout
  psql ${DB_URI} <<EOF
${PSQL_TABLE_STATS_QUERY};

SELECT * FROM combined_results ORDER BY table_name ASC;
EOF

  # Run the query with non-deterministic size column excluded, and export to file for later diffing.
  psql ${DB_URI} <<EOF > ${EXPORT_FILENAME}
${PSQL_TABLE_STATS_QUERY};

SELECT table_name, row_count, hash FROM combined_results ORDER BY table_name ASC;
EOF
}

function _validate_target_db_is_safe_to_migrate() {
  local source_db_uri="$1"
  local target_db_uri="$2"

  echo -n "Checking target DB is in a safe state to receive data ... "

  local source_db_tables=$(psql "$source_db_uri" <<EOF
COPY (
  SELECT string_agg(' ', table_name)
  FROM information_schema.tables
  WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE'
  AND table_name != 'alembic_version'
) TO STDOUT;
EOF
)

  local safe=1
  for tbl in ${source_db_tables}; do
    local result=$(psql "$target_db_uri" -c "COPY (SELECT coalesce(COUNT(*)::text, 'null') FROM ${tbl}) TO STDOUT")
    if [ "${result}" != "0" ]; then
      [ "${safe}" -eq 1 ] && echo 'error. Some tables to be migrated already contain data in the target DB.'
      echo "   ${tbl} has ${result} rows"
      safe=0
    fi
  done

  if [ "${safe}" -eq 0 ]; then
    exit 1;
  fi

  echo "done."
}

function _bail_if_not_aws_cloudshell() {
  if [ "$AWS_EXECUTION_ENV" != "CloudShell" ]; then
    echo "WARNING: This script should not be run locally against RDS Databases. Open AWS Console and use CloudShell instead."
    exit 1;
  fi
}

function run_pre_award_db_migration() {
  local source_app="$1"
  local source_uri="$2"
  local target_uri="$3"

  if [ -n "${source_app}" ]; then
    echo "Source app defined as ${source_app}. Expecting to run in AWS CloudShell against RDS databases."

    _bail_if_not_aws_cloudshell

    # Kill all processes in the same group (eg bastion subshells) on exit
    trap 'kill 0' EXIT

    echo -n "Resolving RDS DB URIs and creating bastion tunnels ... "

    source_uri=$(setup_bastion_for_db_connection_and_get_uri "${source_app}" "copilot-service" "${source_app}" 15432)
    target_uri=$(setup_bastion_for_db_connection_and_get_uri "${source_app}" "aws:cloudformation:logical-id" "fsdpreawardstoresclusterAuroraSecret" 15433)

    echo "done."

    echo -n "Giving bastion tunnels some time to connect ... "
    sleep 5
    echo "done."
  else
    echo "Source and target URI defined. Expecting to run locally against local databases."
    echo -e "SOURCE_URI=${source_uri}\nTARGET_URI=${target_uri}\n===\n"
  fi

  _validate_target_db_is_safe_to_migrate "${source_uri}" "${target_uri}"

  echo "--- pre_migrate_source_db_stats.txt ---"
  _get_table_stats "${source_uri}" "pre_migrate_source_db_stats.txt"
  echo -e "=======================================\n"


  echo "--- pre_migrate_target_db_stats.txt ---"
  _get_table_stats "${target_uri}" "pre_migrate_target_db_stats.txt"
  echo -e "=======================================\n===\n"

  echo "Doing dump and restore..."
  pg_dump --verbose --data-only --format custom --exclude-table alembic_version $source_uri 2>/dev/null | pg_restore --verbose --data-only --format custom --dbname $target_uri || true
  psql ${target_uri} -c "ANALYZE;"
  echo -e "Completed dump and restore.\n\n===\n"

  echo "--- post_migrate_target_db_stats.txt ---"
  _get_table_stats "${target_uri}" "post_migrate_target_db_stats.txt"
  echo -e "========================================\n"

  set +e  # Don't exit the script if the diff comes back with something.
  diff --side-by-side "pre_migrate_source_db_stats.txt" "post_migrate_target_db_stats.txt" > pre_and_post_diff.txt

  if [ "$?" -eq 0 ]; then
    echo -e "HOORAY:\n   Database migration SUCCESSFUL."
  else
    echo -e "WARNING:\n   Database dump FAILED.\n   Database dump FAILED.\n   Database dump FAILED.\n"
    cat pre_and_post_diff.txt
  fi
}
