MYPY_DIRS := $(shell find functions layer ! -path '*.egg-info*' -type d -maxdepth 1 -mindepth 1 | xargs)
ARTIFACTS_DIR ?= build
VENV_DIR=.venv
PYTHON=$(VENV_DIR)/bin/python

.PHONY: test
test:
	pytest

.PHONY: develop
develop:
	python -m venv $(VENV_DIR)
	@echo ". $(VENV_DIR)/bin/activate"
	$(PYTHON) -m pip install --upgrade pip
	$(PYTHON) -m pip install -U -r requirements-dev.txt

.PHONY: build
build:
	rm -rf dist || true
	python -m build -w

.PHONY: build_layer
build_layer: build
	rm -rf "$(ARTIFACTS_DIR)/python" || true
	mkdir -p "$(ARTIFACTS_DIR)/python"
	python -m pip install -r requirements.txt -t "$(ARTIFACTS_DIR)/python"
	python -m pip install dist/*.whl -t "$(ARTIFACTS_DIR)/python"

.PHONY: package_layer
package_layer: build build_layer
	cd "$(ARTIFACTS_DIR)"; zip -rq ../layer.zip python

.PHONY: build-FsdServerlessFunctionLayer
build-FsdServerlessFunctionLayer: build build_layer