# Copyright 2020 IBM Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

.DEFAULT_GOAL:=help

# Dependence tools
CONTAINER_CLI ?= $(shell basename $(shell which docker))
KUBECTL ?= $(shell which kubectl)
OPERATOR_SDK ?= $(shell which operator-sdk)
OPM ?= $(shell which opm)
KUSTOMIZE ?= $(shell which kustomize)
KUSTOMIZE_VERSION=v3.8.7
HELM_OPERATOR_VERSION=v1.4.2
OPM_VERSION=v1.15.2
YQ_VERSION=3.4.1

# Specify whether this repo is build locally or not, default values is '1';
# If set to 1, then you need to also set 'DOCKER_USERNAME' and 'DOCKER_PASSWORD'
# environment variables before build the repo.
BUILD_LOCALLY ?= 1

VCS_URL = $(shell git config --get remote.origin.url)
VCS_REF ?= $(shell git rev-parse HEAD)
VERSION ?= $(shell cat RELEASE_VERSION)
PREVIOUS_VERSION ?= $(shell cat PREVIOUS_VERSION)

LOCAL_OS := $(shell uname)
ifeq ($(LOCAL_OS),Linux)
    TARGET_OS ?= linux
    XARGS_FLAGS="-r"
	STRIP_FLAGS=
else ifeq ($(LOCAL_OS),Darwin)
    TARGET_OS ?= darwin
    XARGS_FLAGS=
	STRIP_FLAGS="-x"
else
    $(error "This system's OS $(LOCAL_OS) isn't recognized/supported")
endif

ARCH := $(shell uname -m)
LOCAL_ARCH := "amd64"
ifeq ($(ARCH),x86_64)
    LOCAL_ARCH="amd64"
else ifeq ($(ARCH),ppc64le)
    LOCAL_ARCH="ppc64le"
else ifeq ($(ARCH),s390x)
    LOCAL_ARCH="s390x"
else
    $(error "This system's ARCH $(ARCH) isn't recognized/supported")
endif

# Current Operator image name
OPERATOR_IMAGE_NAME ?= ibm-crossplane-operator
# Current Operator bundle image name
BUNDLE_IMAGE_NAME ?= ibm-crossplane-operator-bundle

# Options for 'bundle-build'
ifneq ($(origin CHANNELS), undefined)
BUNDLE_CHANNELS := --channels=$(CHANNELS)
endif
ifneq ($(origin DEFAULT_CHANNEL), undefined)
BUNDLE_DEFAULT_CHANNEL := --default-channel=$(DEFAULT_CHANNEL)
endif
BUNDLE_METADATA_OPTS ?= $(BUNDLE_CHANNELS) $(BUNDLE_DEFAULT_CHANNEL)

ifeq ($(BUILD_LOCALLY),0)
    export CONFIG_DOCKER_TARGET = config-docker
	# Default image repo
	REGISTRY ?= hyc-cloud-private-integration-docker-local.artifactory.swg-devops.com/ibmcom
else
	REGISTRY ?= hyc-cloud-private-scratch-docker-local.artifactory.swg-devops.com/ibmcom
endif

include common/Makefile.common.mk

############################################################
##@ Develement tools
############################################################

OS    = $(shell uname -s | tr '[:upper:]' '[:lower:]')
ARCH  = $(shell uname -m | sed 's/x86_64/amd64/')
OSOPER   = $(shell uname -s | tr '[:upper:]' '[:lower:]' | sed 's/darwin/apple-darwin/' | sed 's/linux/linux-gnu/')
ARCHOPER = $(shell uname -m )

tools: kustomize helm-operator opm yq ## Install all development tools

kustomize: ## Install kustomize
ifeq (, $(shell which kustomize 2>/dev/null))
	@{ \
	set -e ;\
	mkdir -p bin ;\
	echo "Downloading kustomize ...";\
	curl -sSLo - https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize/$(KUSTOMIZE_VERSION)/kustomize_$(KUSTOMIZE_VERSION)_$(OS)_$(ARCH).tar.gz | tar xzf - -C bin/ ;\
	}
KUSTOMIZE=$(realpath ./bin/kustomize)
else
KUSTOMIZE=$(shell which kustomize)
endif

helm-operator: ## Install helm-operator
ifeq (, $(shell which helm-operator 2>/dev/null))
	@{ \
	set -e ;\
	mkdir -p bin ;\
	echo "Downloading helm-operator ...";\
	curl -LO https://github.com/operator-framework/operator-sdk/releases/download/$(HELM_OPERATOR_VERSION)/helm-operator-$(HELM_OPERATOR_VERSION)-$(ARCHOPER)-$(OSOPER) ;\
	mv helm-operator-$(HELM_OPERATOR_VERSION)-$(ARCHOPER)-$(OSOPER) ./bin/helm-operator ;\
	chmod +x ./bin/helm-operator ;\
	}
HELM_OPERATOR=$(realpath ./bin/helm-operator)
else
HELM_OPERATOR=$(shell which helm-operator)
endif

opm: ## Install operator registry opm
ifeq (, $(shell which opm 2>/dev/null))
	@{ \
	set -e ;\
	mkdir -p bin ;\
	echo "Downloading opm ...";\
	curl -LO https://github.com/operator-framework/operator-registry/releases/download/$(OPM_VERSION)/$(OS)-amd64-opm ;\
	mv $(OS)-amd64-opm ./bin/opm ;\
	chmod +x ./bin/opm ;\
	}
OPM=$(realpath ./bin/opm)
else
OPM=$(shell which opm)
endif

yq: ## Install yq, a yaml processor
ifeq (, $(shell which yq 2>/dev/null))
	@{ \
	set -e ;\
	mkdir -p bin ;\
	$(eval ARCH := $(shell uname -m|sed 's/x86_64/amd64/')) \
	echo "Downloading yq ...";\
	curl -LO https://github.com/mikefarah/yq/releases/download/$(YQ_VERSION)/yq_$(OS)_$(ARCH);\
	mv yq_$(OS)_$(ARCH) ./bin/yq ;\
	chmod +x ./bin/yq ;\
	}
YQ=$(realpath ./bin/yq)
else
YQ=$(shell which yq)
endif

############################################################
##@ Development
############################################################

check: lint-all ## Check all files lint error
	./common/scripts/lint-csv.sh

run: helm-operator ## Run against the configured Kubernetes cluster in ~/.kube/config
	$(HELM_OPERATOR) run

install: kustomize ## Install CRDs, controller, and sample CR to a cluster
	$(KUSTOMIZE) build config/development | kubectl apply -f -
	$(KUSTOMIZE) build config/samples | kubectl apply -f -

uninstall: kustomize ## Uninstall CRDs, controller, and sample CR from a cluster
	$(KUSTOMIZE) build config/samples | kubectl delete --ignore-not-found -f -
	$(KUSTOMIZE) build config/development | kubectl delete --ignore-not-found -f -

deploy-csv:
	$(eval NAMESPACE := $(shell oc project -q))
	- cat bundle/manifests/ibm-crossplane-operator.clusterserviceversion.yaml \
		| sed -e "s|image: quay.io/opencloudio/ibm-crossplane-operator:latest|image: $(REGISTRY)/$(OPERATOR_IMAGE_NAME)-$(ARCH):dev|g" \
		| sed -e "s|namespace: placeholder|namespace: $(NAMESPACE)|g" | kubectl apply -f -

clean-cluster: ## Clean up all the resources left in the Kubernetes cluster
	@echo ....... Cleaning up .......
	- kubectl get platformapis -o name | xargs kubectl delete
	- kubectl get csv -o name | grep ibm-crossplane | xargs kubectl delete
	- kubectl get sub -o name | grep ibm-crossplane | xargs kubectl delete
	- kubectl get installplans | grep ibm-crossplane | awk '{print $$1}' | xargs kubectl delete installplan
	- kubectl get serviceaccounts -o name | grep ibm-crossplane | xargs kubectl delete
	- kubectl get clusterrole -o name | grep ibm-crossplane | xargs kubectl delete
	- kubectl get clusterrolebinding -o name | grep ibm-crossplane | xargs kubectl delete	
	- kubectl get crd -o name | grep platformapi | xargs kubectl delete

global-pull-secrets: ## Update global pull secrets to use artifactory registries
	./common/scripts/update_global_pull_secrets.sh

deploy-catalog: build-catalog ## Deploy the operator bundle catalogsource for testing
	./common/scripts/update_catalogsource.sh $(OPERATOR_IMAGE_NAME) $(REGISTRY)/$(OPERATOR_IMAGE_NAME)-catalog:$(VERSION)

undeploy-catalog: ## Undeploy the operator bundle catalogsource
	- kubectl -n openshift-marketplace delete catalogsource $(OPERATOR_IMAGE_NAME)

############################################################
##@ Test
############################################################

test: ## Run unit test on prow
	@echo good

############################################################
##@ Build
############################################################

# build: build-image-amd64 build-image-ppc64le build-image-s390x ## Build multi-arch operator image
build: build-image-amd64 ## Build multi-arch operator image

build-dev: build-image-dev ## Build operator image for development

build-catalog: build-bundle-image build-catalog-source ## Build bundle image and catalog source image for development

# Build bundle image
build-bundle-image: 
	$(eval ARCH := $(shell uname -m|sed 's/x86_64/amd64/'))
	@cp -f bundle/manifests/ibm-crossplane-operator.clusterserviceversion.yaml /tmp/ibm-crossplane-operator.clusterserviceversion.yaml
	@$(YQ) d -i bundle/manifests/ibm-crossplane-operator.clusterserviceversion.yaml "spec.replaces"
	$(CONTAINER_CLI) build -f bundle.Dockerfile -t $(REGISTRY)/$(BUNDLE_IMAGE_NAME)-$(ARCH):$(VERSION) .
	$(CONTAINER_CLI) push $(REGISTRY)/$(BUNDLE_IMAGE_NAME)-$(ARCH):$(VERSION)
	@mv /tmp/ibm-crossplane-operator.clusterserviceversion.yaml bundle/manifests/ibm-crossplane-operator.clusterserviceversion.yaml

# Build catalog source
build-catalog-source:
	$(OPM) -u $(CONTAINER_CLI) index add --bundles $(REGISTRY)/$(BUNDLE_IMAGE_NAME)-$(ARCH):$(VERSION) --tag $(REGISTRY)/$(OPERATOR_IMAGE_NAME)-catalog:$(VERSION)
	$(CONTAINER_CLI) push $(REGISTRY)/$(OPERATOR_IMAGE_NAME)-catalog:$(VERSION)

# Build image for development
build-image-dev:
	$(eval ARCH := $(shell uname -m|sed 's/x86_64/amd64/'))
	$(CONTAINER_CLI) build -t $(REGISTRY)/$(OPERATOR_IMAGE_NAME)-$(ARCH):dev \
	--build-arg VCS_REF=$(VCS_REF) --build-arg VCS_URL=$(VCS_URL) \
	-f Dockerfile .
	$(CONTAINER_CLI) push $(REGISTRY)/$(OPERATOR_IMAGE_NAME)-$(ARCH):dev

# Build image for amd64
build-image-amd64: $(CONFIG_DOCKER_TARGET)
	$(eval ARCH := $(shell uname -m|sed 's/x86_64/amd64/'))
	$(CONTAINER_CLI) build -t $(REGISTRY)/$(OPERATOR_IMAGE_NAME)-$(ARCH):$(VERSION) \
	--build-arg VCS_REF=$(VCS_REF) --build-arg VCS_URL=$(VCS_URL) \
	-f Dockerfile .
	@if [ $(BUILD_LOCALLY) -ne 1 ]; then $(CONTAINER_CLI) push $(REGISTRY)/$(OPERATOR_IMAGE_NAME)-amd64:$(VERSION); fi

# Build image for ppc64le
build-image-ppc64le: $(CONFIG_DOCKER_TARGET)
	$(CONTAINER_CLI) build -t $(REGISTRY)/$(OPERATOR_IMAGE_NAME)-ppc64le:$(VERSION) \
	--build-arg VCS_REF=$(VCS_REF) --build-arg VCS_URL=$(VCS_URL) \
	-f Dockerfile.ppc64le .
	@if [ $(BUILD_LOCALLY) -ne 1 ]; then $(CONTAINER_CLI) push $(REGISTRY)/$(OPERATOR_IMAGE_NAME)-ppc64le:$(VERSION); fi

# Build image for s390x
build-image-s390x: $(CONFIG_DOCKER_TARGET)
	$(CONTAINER_CLI) build -t $(REGISTRY)/$(OPERATOR_IMAGE_NAME)-s390x:$(VERSION) \
	--build-arg VCS_REF=$(VCS_REF) --build-arg VCS_URL=$(VCS_URL) \
	-f Dockerfile.s390x .
	@if [ $(BUILD_LOCALLY) -ne 1 ]; then $(CONTAINER_CLI) push $(REGISTRY)/$(OPERATOR_IMAGE_NAME)-s390x:$(VERSION); fi

############################################################
##@ Release
############################################################

bundle: kustomize ## Generate bundle manifests and metadata, then validate the generated files
	$(OPERATOR_SDK) generate kustomize manifests -q
	- make bundle-manifests CHANNELS=v3 DEFAULT_CHANNEL=v3

bundle-manifests:
	$(KUSTOMIZE) build config/manifests | $(OPERATOR_SDK) generate bundle \
	-q --overwrite --version $(VERSION) $(BUNDLE_METADATA_OPTS)
	$(OPERATOR_SDK) bundle validate ./bundle
	@./common/scripts/adjust_manifests.sh $(VERSION) $(PREVIOUS_VERSION)

images: build-image-amd64 ## Build and publish the multi-arch operator image
ifeq ($(TARGET_OS),$(filter $(TARGET_OS),linux darwin))
	@curl -L -o /tmp/manifest-tool https://github.com/estesp/manifest-tool/releases/download/v1.0.3/manifest-tool-$(TARGET_OS)-amd64
	@chmod +x /tmp/manifest-tool
	@echo "Merging and push multi-arch image $(REGISTRY)/$(OPERATOR_IMAGE_NAME):latest"
	/tmp/manifest-tool push from-args --platforms linux/amd64 --template $(REGISTRY)/$(OPERATOR_IMAGE_NAME)-ARCH:$(VERSION) --target $(REGISTRY)/$(OPERATOR_IMAGE_NAME):latest
	@echo "Merging and push multi-arch image $(REGISTRY)/$(OPERATOR_IMAGE_NAME):$(VERSION)"
	/tmp/manifest-tool push from-args --platforms linux/amd64 --template $(REGISTRY)/$(OPERATOR_IMAGE_NAME)-ARCH:$(VERSION) --target $(REGISTRY)/$(OPERATOR_IMAGE_NAME):$(VERSION)
endif

# images: build-image-amd64 build-image-ppc64le build-image-s390x ## Build and publish the multi-arch operator image
# ifeq ($(TARGET_OS),$(filter $(TARGET_OS),linux darwin))
#	@curl -L -o /tmp/manifest-tool https://github.com/estesp/manifest-tool/releases/download/v1.0.3/manifest-tool-$(TARGET_OS)-amd64
#	@chmod +x /tmp/manifest-tool
#	@echo "Merging and push multi-arch image $(REGISTRY)/$(OPERATOR_IMAGE_NAME):latest"
#	/tmp/manifest-tool push from-args --platforms linux/amd64,linux/ppc64le,linux/s390x --template $(REGISTRY)/$(OPERATOR_IMAGE_NAME)-ARCH:$(VERSION) --target $(REGISTRY)/$(OPERATOR_IMAGE_NAME):latest
#	@echo "Merging and push multi-arch image $(REGISTRY)/$(OPERATOR_IMAGE_NAME):$(VERSION)"
#	/tmp/manifest-tool push from-args --platforms linux/amd64,linux/ppc64le,linux/s390x --template $(REGISTRY)/$(OPERATOR_IMAGE_NAME)-ARCH:$(VERSION) --target $(REGISTRY)/$(OPERATOR_IMAGE_NAME):$(VERSION)
# endif

############################################################
##@ Help
############################################################
help: ## Display this help
	@echo "Usage:\n  make \033[36m<target>\033[0m"
	@awk 'BEGIN {FS = ":.*##"}; \
		/^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)