.DEFAULT_GOAL=help

# Required for globs to work correctly
SHELL:=/bin/bash

.EXPORT_ALL_VARIABLES:

.PHONY: all tools format lint

all: format lint

tools:  ## Ensure required tools exist
	@set -euo pipefail; \
	for UTIL in tflint tfenv; do \
		which $${UTIL} >/dev/null 2>&1 || (echo "==> Please install $${UTIL}"; false); \
	done

format: tools  ## Format all go code
	@echo "==> Formatting ..."
	@terraform fmt -recursive

lint: tools  ## Run static code analysis
	@echo "==> Linting ..."
	@tflint --recursive .

help:  ## Print list of Makefile targets
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  cut -d ":" -f1- | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
