# Unit Testing

We write unit tests using Pytest.

To run all tests in a development environment run:
```bash
    pytest
```

## Pytest Fixtures
Fixtures shared across a single project are contained in `conftest.py`.

fsd_utils provides some common fixtures for dealing with database testing, see [FSD Utils README](https://github.com/communitiesuk/funding-service-design-utils?tab=readme-ov-file#fixtures)