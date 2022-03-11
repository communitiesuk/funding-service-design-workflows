# funding-design-service-workflows

This repo containes workflow templates that individual workflows can be added to your repo workflow as required.

### Work flow templates for DLUHC

File: deploy.yml

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



