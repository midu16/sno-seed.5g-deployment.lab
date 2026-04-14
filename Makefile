.PHONY: help fetch-certificate registry-pull-secret update-sshkey download-oc-tools generate-openshift-install imageset-config.yml imageset-ga imageset-prega clean

# Default target
.DEFAULT_GOAL := help

# Load OCP_VERSION and DEPLOYMENT_TYPE from VERSION file if it exists
ifeq ($(VERSION),)
    ifneq (,$(wildcard VERSION))
        include VERSION
        export OCP_VERSION
        export DEPLOYMENT_TYPE
        VERSION := $(OCP_VERSION)
    endif
endif

# Colors for output
GREEN  := \033[0;32m
YELLOW := \033[0;33m
RED    := \033[0;31m
BLUE   := \033[0;34m
NC     := \033[0m # No Color

# Detect if running as root
ifeq ($(shell id -u),0)
    SUDO :=
else
    SUDO := sudo
endif

help: ## Show this help message
	@echo "$(GREEN)SNO Seed Cluster - Makefile Help$(NC)"
	@echo ""
	@if [ -f VERSION ]; then \
		echo "$(BLUE)Default OCP Version (from VERSION file): $(shell grep OCP_VERSION VERSION | cut -d= -f2)$(NC)"; \
		echo "$(BLUE)Override with: make <target> VERSION=<version>$(NC)"; \
		echo ""; \
	fi
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-30s$(NC) %s\n", $$1, $$2}'
	@echo ""

fetch-certificate: ## Fetch registry certificate and update install-config.yaml
	@echo "$(GREEN)Fetching certificate from registry...$(NC)"
	@if [ -z "$(REGISTRY_URL)" ]; then \
		REGISTRY_URL="infra.5g-deployment.lab:8443"; \
	fi; \
	echo "$(BLUE)Registry URL: $$REGISTRY_URL$(NC)"; \
	REGISTRY_HOST=$$(echo $$REGISTRY_URL | cut -d: -f1); \
	REGISTRY_PORT=$$(echo $$REGISTRY_URL | cut -d: -f2); \
	if [ -z "$$REGISTRY_PORT" ]; then \
		REGISTRY_PORT="443"; \
	fi; \
	echo "$(BLUE)Fetching certificate from $$REGISTRY_HOST:$$REGISTRY_PORT$(NC)"; \
	CERT=$$(openssl s_client -connect $$REGISTRY_HOST:$$REGISTRY_PORT -servername $$REGISTRY_HOST \
		</dev/null 2>/dev/null \
		| sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p'); \
	if [ -z "$$CERT" ]; then \
		echo "$(RED)✗ Failed to fetch certificate$(NC)"; \
		exit 1; \
	fi; \
	echo "$(GREEN)✓ Certificate fetched successfully$(NC)"; \
	if [ -f workingdir/install-config.yaml ]; then \
		echo "$(BLUE)Updating install-config.yaml with certificate...$(NC)"; \
		awk -v cert="$$CERT" '/additionalTrustBundle: \|/{print;while((rc=getline)>0 && $$0 ~ /^ /){}print cert;if(rc>0)print;next}1' \
			workingdir/install-config.yaml > workingdir/install-config.yaml.tmp && \
		mv workingdir/install-config.yaml.tmp workingdir/install-config.yaml; \
		echo "$(GREEN)✓ Certificate updated in install-config.yaml$(NC)"; \
	else \
		echo "$(YELLOW)Warning: workingdir/install-config.yaml not found$(NC)"; \
	fi

registry-pull-secret: ## Generate base64 pull secret (USERNAME=user PASSWORD=pass REGISTRY_URL=...)
	@echo "$(GREEN)Generating registry pull secret...$(NC)"
	@if [ -z "$(USERNAME)" ] || [ -z "$(PASSWORD)" ]; then \
		echo "$(RED)✗ Error: USERNAME and PASSWORD are required$(NC)"; \
		echo "$(YELLOW)Usage: make registry-pull-secret USERNAME=myuser PASSWORD=mypass$(NC)"; \
		echo "$(YELLOW)Optional: REGISTRY_URL=infra.5g-deployment.lab:8443$(NC)"; \
		exit 1; \
	fi; \
	if [ -z "$(REGISTRY_URL)" ]; then \
		REGISTRY_URL="infra.5g-deployment.lab:8443"; \
	fi; \
	echo "$(BLUE)Registry URL: $$REGISTRY_URL$(NC)"; \
	echo "$(BLUE)Username: $(USERNAME)$(NC)"; \
	AUTH_ENCODED=$$(echo -n '$(USERNAME):$(PASSWORD)' | base64 -w 0); \
	PULL_SECRET="{\"auths\":{\"$$REGISTRY_URL\":{\"auth\":\"$$AUTH_ENCODED\"}}}"; \
	echo "$(GREEN)✓ Pull secret generated$(NC)"; \
	mkdir -p .docker; \
	echo "$$PULL_SECRET" > .docker/config.json; \
	echo "$(GREEN)✓ Saved to .docker/config.json$(NC)"; \
	if [ -f workingdir/install-config.yaml ]; then \
		echo "$(BLUE)Updating install-config.yaml with pull secret...$(NC)"; \
		sed -i "s|pullSecret:.*|pullSecret: '$$PULL_SECRET'|" workingdir/install-config.yaml; \
		echo "$(GREEN)✓ Pull secret updated in install-config.yaml$(NC)"; \
	fi

update-sshkey: ## Update SSH key in install-config.yaml (SSHKEY_FILE=~/.ssh/id_rsa.pub)
	@echo "$(GREEN)Updating SSH key in install-config.yaml...$(NC)"
	@if [ -z "$(SSHKEY_FILE)" ]; then \
		echo "$(RED)✗ Error: SSHKEY_FILE parameter is required$(NC)"; \
		echo "$(YELLOW)Usage: make update-sshkey SSHKEY_FILE=/path/to/id_rsa.pub$(NC)"; \
		exit 1; \
	fi; \
	SSHKEY_PATH=$$(eval echo $(SSHKEY_FILE)); \
	echo "$(BLUE)SSH Key File: $$SSHKEY_PATH$(NC)"; \
	if [ ! -f "$$SSHKEY_PATH" ]; then \
		echo "$(RED)✗ Error: SSH key file not found: $$SSHKEY_PATH$(NC)"; \
		exit 1; \
	fi; \
	SSHKEY=$$(cat "$$SSHKEY_PATH"); \
	if [ -f workingdir/install-config.yaml ]; then \
		sed -i "s|sshKey:.*|sshKey: '$$SSHKEY'|" workingdir/install-config.yaml; \
		echo "$(GREEN)✓ SSH key updated in install-config.yaml$(NC)"; \
	else \
		echo "$(RED)✗ Error: workingdir/install-config.yaml not found$(NC)"; \
		exit 1; \
	fi

download-oc-tools: ## Download oc-mirror and oc tools (VERSION from VERSION file or specify VERSION=x.y.z)
	@echo "$(GREEN)Downloading OpenShift client tools...$(NC)"
	@if [ -z "$(VERSION)" ]; then \
		echo "$(RED)✗ Error: VERSION variable is not set and VERSION file not found.$(NC)"; \
		echo "$(YELLOW)Usage: make download-oc-tools VERSION=4.18.27$(NC)"; \
		echo "$(YELLOW)Or add VERSION file with: OCP_VERSION=4.18.27$(NC)"; \
		exit 1; \
	fi; \
	if [ ! -f ./00_client_download.sh ]; then \
		echo "$(RED)✗ Error: ./00_client_download.sh not found$(NC)"; \
		exit 1; \
	fi; \
	chmod +x ./00_client_download.sh; \
	echo "$(BLUE)Version: $(VERSION)$(NC)"; \
	OCP_VERSION="$(VERSION)" ./00_client_download.sh || { \
		echo "$(RED)✗ Failed to download OpenShift client tools$(NC)"; \
		exit 1; \
	}; \
	if [ -f ./bin/oc ]; then ./bin/oc version --client; fi; \
	if [ -f ./bin/oc-mirror ]; then ./bin/oc-mirror version; fi

generate-openshift-install: ## Generate openshift-install (RELEASE_IMAGE=registry/image:tag)
	@echo "$(GREEN)Generating openshift-install...$(NC)"
	@if [ -z "$(RELEASE_IMAGE)" ]; then \
		echo "$(RED)✗ Error: RELEASE_IMAGE must be set.$(NC)"; \
		echo "$(YELLOW)Usage: make generate-openshift-install RELEASE_IMAGE=infra.5g-deployment.lab:8443/seed/openshift/release-images:4.18.27-x86_64$(NC)"; \
		exit 1; \
	fi; \
	if [ ! -f ./bin/oc ]; then \
		echo "$(RED)✗ Error: ./bin/oc not found. Run 'make download-oc-tools VERSION=<version>' first$(NC)"; \
		exit 1; \
	fi; \
	if [ ! -f .docker/config.json ]; then \
		echo "$(RED)✗ Error: .docker/config.json not found. Run 'make registry-pull-secret' first$(NC)"; \
		exit 1; \
	fi; \
	mkdir -p ./bin; \
	echo "$(BLUE)Release Image: $(RELEASE_IMAGE)$(NC)"; \
	echo "$(BLUE)Extracting openshift-install...$(NC)"; \
	DOCKER_CONFIG=.docker ./bin/oc adm release extract \
		--command=openshift-install \
		--to=./bin/ \
		--insecure=true \
		"$(RELEASE_IMAGE)"; \
	chmod +x ./bin/openshift-install; \
	echo "$(GREEN)✓ openshift-install extracted to ./bin/openshift-install$(NC)"; \
	./bin/openshift-install version

imageset-config.yml: ## Generate imageset-config.yml (OCP_VERSION from VERSION file or specify OCP_VERSION=x.y.z)
	@echo "$(GREEN)Generating imageset-config.yml...$(NC)"
	@if [ -z "$(OCP_VERSION)" ]; then \
		echo "$(RED)✗ Error: OCP_VERSION variable is not set and VERSION file not found.$(NC)"; \
		echo "$(YELLOW)Usage: make imageset-config.yml OCP_VERSION=4.18.27$(NC)"; \
		echo "$(YELLOW)Or add VERSION file with: OCP_VERSION=4.18.27$(NC)"; \
		exit 1; \
	fi; \
	if [ ! -f ./imageset-config.sh ]; then \
		echo "$(RED)✗ Error: ./imageset-config.sh not found$(NC)"; \
		exit 1; \
	fi; \
	chmod +x ./imageset-config.sh; \
	OCP_VERSION="$(OCP_VERSION)" \
		SOURCE_INDEX="$${SOURCE_INDEX:-registry.redhat.io/redhat/redhat-operator-index:v$$(echo $(OCP_VERSION) | cut -d. -f1,2)}" \
		IMAGESET_OUTPUT_FILE="imageset-config.yml" \
		./imageset-config.sh -g || { \
		echo "$(RED)✗ Failed to generate imageset-config.yml$(NC)"; \
		exit 1; \
	}; \
	echo "$(GREEN)✓ Generated imageset-config.yml$(NC)"

imageset-ga: ## Generate imageset for GA deployment (VERSION from VERSION file or specify VERSION=4.18.27)
	@echo "$(GREEN)Generating ImageSet Configuration for GA deployment...$(NC)"
	@if [ -z "$(VERSION)" ]; then \
		echo "$(RED)✗ Error: VERSION variable is not set.$(NC)"; \
		echo "$(YELLOW)Usage: make imageset-ga VERSION=4.18.27$(NC)"; \
		echo "$(YELLOW)Or set in VERSION file: OCP_VERSION=4.18.27$(NC)"; \
		exit 1; \
	fi; \
	if [ ! -f ./generate-imageset-dynamic.sh ]; then \
		echo "$(RED)✗ Error: ./generate-imageset-dynamic.sh not found$(NC)"; \
		exit 1; \
	fi; \
	chmod +x ./generate-imageset-dynamic.sh; \
	./generate-imageset-dynamic.sh --ga $(VERSION) -o imageset-config.yml; \
	echo "$(GREEN)✓ Generated imageset-config.yml for GA deployment$(NC)"

imageset-prega: ## Generate imageset for PreGA deployment (VERSION from VERSION file or specify VERSION=4.22.0)
	@echo "$(GREEN)Generating ImageSet Configuration for PreGA deployment...$(NC)"
	@if [ -z "$(VERSION)" ]; then \
		echo "$(RED)✗ Error: VERSION variable is not set.$(NC)"; \
		echo "$(YELLOW)Usage: make imageset-prega VERSION=4.22.0$(NC)"; \
		echo "$(YELLOW)Or set in VERSION file: OCP_VERSION=4.22.0$(NC)"; \
		exit 1; \
	fi; \
	if [ ! -f ./generate-imageset-dynamic.sh ]; then \
		echo "$(RED)✗ Error: ./generate-imageset-dynamic.sh not found$(NC)"; \
		exit 1; \
	fi; \
	chmod +x ./generate-imageset-dynamic.sh; \
	./generate-imageset-dynamic.sh --prega $(VERSION) -o imageset-config.yml; \
	echo "$(GREEN)✓ Generated imageset-config.yml for PreGA deployment$(NC)"

create-agent-iso: ## Create agent.iso for SNO installation
	@echo "$(GREEN)Creating agent.iso...$(NC)"
	@if [ ! -f ./bin/openshift-install ]; then \
		echo "$(RED)✗ Error: ./bin/openshift-install not found. Run 'make generate-openshift-install' first$(NC)"; \
		exit 1; \
	fi; \
	mkdir -p ./seed; \
	cp workingdir/install-config.yaml ./seed/; \
	cp workingdir/agent-config.yaml ./seed/; \
	if [ -d workingdir/openshift ]; then \
		cp -r workingdir/openshift ./seed/; \
	fi; \
	echo "$(BLUE)Generating agent.iso...$(NC)"; \
	./bin/openshift-install agent create image --dir ./seed/ --log-level=debug; \
	echo "$(GREEN)✓ agent.iso created at ./seed/agent.x86_64.iso$(NC)"

clean: ## Clean generated files
	@echo "$(GREEN)Cleaning generated files...$(NC)"
	@rm -rf ./bin/
	@rm -rf ./seed/
	@rm -f imageset-config.yml
	@rm -f workingdir/install-config.yaml.bak
	@echo "$(GREEN)✓ Clean complete$(NC)"
