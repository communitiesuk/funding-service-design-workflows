#!/bin/bash

set -e  # Exit script if any commands fail

function usage() {
    # TODO: take a flag that can read creds from AWS to derive these things
    echo "Usage: $0 [-a <pre_award_store_service_name> | -s <source_database_uri> -t <target_database_uri>]"
    echo ""
    echo "Use the \`-a\` option only when running in AWS CloudShell against RDS databases."
    echo "Use the \`-s\` and \`-t\` options together when running locally against local databases."
}

function parse_args() {
    while getopts 'a:s:t:' opt; do
        case "${opt}" in
            a)
                SOURCE_APP=${OPTARG}
                ;;
            s)
                SOURCE_URI=${OPTARG}
                ;;
            t)
                TARGET_URI=${OPTARG}
                ;;
            *)
                usage
                exit 1;
            ;;
        esac
    done
    shift $((OPTIND-1))

    if [ -n "${SOURCE_APP}" ] && ([ -n "${SOURCE_URI}" ] || [ -n "${TARGET_URI}" ]); then
        usage;
        exit 1;
    fi
}

# ENTRYPOINT: this only runs when the script is run directly.
if [ $(basename "$0") == "migrate-pre-award-db.sh" ]; then
    parse_args $@

    # Load functions with the migration logic.
    source ./scripts/_migrate-pre-award-service-functions.sh

    run_pre_award_db_migration "${SOURCE_APP}" "${SOURCE_URI}" "${TARGET_URI}"
fi
