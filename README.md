# funding-design-service-workflows

This repo containes workflow templates that individual workflows can be added to your repo workflow as required.

## Work flow templates for DLUHC

### File: deploy.yml

Workflow name: Test and Deploy to PaaS

Desc:  This workflow automates the process of testing and deploying Python application to PaaS.  It runs unit tests, deploys application to Dev and Test then runs security tests against the deployed applications.  The application address used by the security test is currently hard coded.

Usage:
```yaml
jobs:
  test_and_deploy:
    uses: communitiesuk/funding-design-service-workflows/.github/workflows/deploy.yml@main
    with:
      app_name: ${{ github.event.repository.name }}
    secrets:
      CF_API: ${{secrets.CF_API}} #required
      CF_ORG: ${{secrets.CF_ORG}} #required
      CF_USER: ${{secrets.CF_USER}} #required
      CF_PASSWORD: ${{secrets.CF_PASSWORD}} #required
      E2E_PAT: ${{secrets.E2E_PAT}} #required for checking out e2e tests repo
```

### File: run-shared-tests.yml
Desc: This workflow is designed to be run after deployment from other workflows. It is used by the main shared workflow to run tests after deployments but is in a separate file so it can be used by workflows that don't use the shared workflow as well (eg. terraform). It runs the performance tests, e2e tests and accessibility tests (there aren't any currently) depending on the values passed in.

Usage:

```yaml

  run_shared_tests_dev:
    uses: communitiesuk/funding-design-service-workflows/.github/workflows/run-shared-tests.yml
    with:
      e2e_tests_target_url_frontend: https://<auth>@frontend.uat.gids.dev
      e2e_tests_target_url_authenticator: https://<auth>@authenticator.uat.gids.dev
      e2e_tests_target_url_form_runner: https://<auth>@forms.uat.gids.dev
      run_performance_tests: true
      run_e2e_tests: true
      run_accessibility_tests: false
    secrets:
       E2E_PAT: ${{secrets.E2E_PAT}}
```


#### Accessibility testing

We typically wait for a service to be deployed to test before running accessibility testing on it. For this reason, tests marked (by pytests mark decorator) as "accessibility" will not be ran until the dev deployment has been made.

We mark a test for accessibility testing as so:

```python
import pytest

@pytest.mark.accessibility
def test_accessibility_feature():
  ...

```

PreRequisites:

The variables required are for the PaaS API.  appropriate credentials should reside in you repos' Secret store.



