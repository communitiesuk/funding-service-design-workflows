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

PreRequisites:

The variables required are for the PaaS API.  appropriate credentials should reside in you repos' Secret store.



