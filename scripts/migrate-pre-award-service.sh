#!/bin/bash

function usage() {
    echo "Usage: $0 -a [fsd-fund-store] -e [dev|test|uat|prod]"
}

function parse_args() {
    while getopts 'a:e:' opt; do
        case "${opt}" in
            a)
                APP_NAME=${OPTARG}
                ;;
            e)
                AWS_ENVIRONMENT=${OPTARG}
                ;;
            *)
                usage
                exit 1;
                ;;
        esac
    done
    shift $((OPTIND-1))

    if [ -z "${APP_NAME}" ] || [ -z "${AWS_ENVIRONMENT}" ]; then
        usage;
        exit 1;
    fi
}

function run_pre_award_service_migration() {
    local app_name="$1"
    local aws_environment="$2"

    # Load functions with the migration logic.
    source ./scripts/_migrate-pre-award-service-functions.sh

    # TODO: Add cases for application-store/assessment-store here.
    case "${app_name}" in
        ${SERVICE_NAME_FUND_STORE})
            ;;
        *)
            usage;
            exit 1;
            ;;
    esac

    case "${aws_environment}" in
        dev|test|uat|prod)
            ;;
        *)
            usage;
            exit 1;
            ;;
    esac

    # Check that we're running via an AWS CloudShell
    _bail_if_not_aws_cloudshell

    # Enable maintenance mode on the frontends
    result=$(print_section_header "Pre-flight checks" false)
    [ "${result}" == "yes" ] && run_pre_flight_checks "${app_name}"

    # Enable maintenance mode on the frontends
    result=$(print_section_header "Enable pre-award maintenance mode" true)
    [ "${result}" == "yes" ] && set_maintenance_mode "true" "${aws_environment}"

    # Scale the app-to-be-migrated down to 0 instances so that nothing is talking to its DB.
    result=$(print_section_header "Scale ${app_name} to 0 instances" true)
    [ "${result}" == "yes" ] && scale_service_instances "${app_name}" 0

    # Run the database migration
    result=$(print_section_header "Run ${app_name} database migration" true)
    [ "${result}" == "yes" ] && run_pre_award_db_migration "${app_name}"

    # Update environment variables (via parameter store) to point at the new combined service
    result=$(print_section_header "Update environment variables for ${app_name} callers" true)
    [ "${result}" == "yes" ] && migrate_environment_variables_for_service "${app_name}" "${aws_environment}"

    # Disable maintenance mode on the frontends
    result=$(print_section_header "Disable maintenance mode" true)
    [ "${result}" == "yes" ] && set_maintenance_mode "false" "${aws_environment}"

    print_section_header "FINISHED" false > /dev/null
}

# ENTRYPOINT: this only runs when the script is run directly.
if [ $(basename "$0") == "migrate-pre-award-service.sh" ]; then
  set -e  # Exit script if any commands fail

  parse_args $@

  run_pre_award_service_migration "${APP_NAME}" "${AWS_ENVIRONMENT}"
fi
