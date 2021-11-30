# Copyright 2021 IBM Corporation
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
SHELL := /bin/bash
CONTAINER_CLI ?= $(shell basename $(shell which docker))
CONTAINER_BUILD_CMD ?= build
BUILDX := $(shell docker buildx version 2>/dev/null | grep buildx)
BUILDX_VERSION := v0.6.1
BUILDX_PLUGIN := ./bin/docker-buildx
KUBECTL ?= $(shell which kubectl)
OPERATOR_SDK ?= $(shell which operator-sdk)
OPM ?= $(shell which opm)
KUSTOMIZE ?= $(shell which kustomize)
KUSTOMIZE_VERSION=v3.8.7
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
GIT_VERSION ?= $(shell git describe --exact-match 2> /dev/null || \
                 	   git describe --match=$(git rev-parse --short=8 HEAD) --always --dirty --abbrev=8)

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

REGISTRY_DAILY ?= hyc-cloud-private-daily-docker-local.artifactory.swg-devops.com/ibmcom

ifeq ($(BUILD_LOCALLY),0)
    export CONFIG_DOCKER_TARGET = config-docker
	# Default image repo
	REGISTRY ?= hyc-cloud-private-integration-docker-local.artifactory.swg-devops.com/ibmcom
else
	REGISTRY ?= hyc-cloud-private-scratch-docker-local.artifactory.swg-devops.com/ibmcom
endif
OPERATOR_IMAGE := $(REGISTRY)/$(OPERATOR_IMAGE_NAME):$(VERSION)

include common/Makefile.common.mk

############################################################
##@ Develement tools
############################################################

OS    := $(shell uname -s | tr '[:upper:]' '[:lower:]')
ARCH  := $(shell uname -m | sed 's/x86_64/amd64/')
OSOPER   := $(shell uname -s | tr '[:upper:]' '[:lower:]' | sed 's/darwin/apple-darwin/' | sed 's/linux/linux-gnu/')
ARCHOPER := $(shell uname -m )

tools: kustomize opm yq ## Install all development tools

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

opm: ## Install operator registry opm
ifeq (, $(shell which opm 2>/dev/null))
	@{ \
	set -e ;\
	mkdir -p bin ;\
	echo "Downloading opm ...";\
	curl -LO https://github.com/operator-framework/operator-registry/releases/download/$(OPM_VERSION)/$(OS)-$(ARCH)-opm ;\
	mv $(OS)-$(ARCH)-opm ./bin/opm ;\
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

buildx:
ifeq (,$(BUILDX))
	@{ \
	set -e ;\
	mkdir -p bin ;\
	$(eval ARCH := $(shell uname -m|sed 's/x86_64/amd64/')) \
	echo "Downloading docker-buildx ...";\
	curl -LO https://github.com/docker/buildx/releases/download/$(BUILDX_VERSION)/buildx-$(BUILDX_VERSION).$(OS)-$(ARCH);\
	mv buildx-$(BUILDX_VERSION).$(OS)-$(ARCH) $(BUILDX_PLUGIN);\
	chmod a+x $(BUILDX_PLUGIN);\
	$(BUILDX_PLUGIN) create --use --platform linux/amd64,linux/ppc64le,linux/2390x;\
	}
endif


kubectl-crossplane: ## build binary needed for docker images
	cd ./ibm-crossplane && go build -o ./../kubectl-crossplane ./cmd/crank
	cd ..
	chmod +x ./kubectl-crossplane

############################################################
##@ Development
############################################################

# artifactory registry
ARTIFACTORY_REGISTRY := hyc-cloud-private-scratch-docker-local.artifactory.swg-devops.com

ifeq ($(OS),darwin)
	MANIFEST_TOOL_ARGS ?= --username $(DOCKER_USERNAME) --password $(DOCKER_PASSWORD)
else
	MANIFEST_TOOL_ARGS ?= 
endif

check: lint-all ## Check all files lint error
	./common/scripts/lint-csv.sh

install: kustomize ## Install CRDs, controller, and sample CR to a cluster
	$(KUSTOMIZE) build config/development | kubectl apply -f -
	$(KUSTOMIZE) build config/samples | kubectl apply -f -
	- kubectl config set-context --current --namespace=ibm-common-services

uninstall: kustomize ## Uninstall CRDs, controller, and sample CR from a cluster
	$(KUSTOMIZE) build config/samples | kubectl delete --ignore-not-found -f -
	$(KUSTOMIZE) build config/development | kubectl delete --ignore-not-found -f -
	- make clean-cluster

install-catalog-source: ## Install the operator catalog source for testing
	./common/scripts/update_catalogsource.sh $(OPERATOR_IMAGE_NAME) $(REGISTRY)/$(OPERATOR_IMAGE_NAME)-catalog:$(VERSION)

uninstall-catalog-source: ## Uninstall the operator catalog source
	- kubectl -n openshift-marketplace delete catalogsource $(OPERATOR_IMAGE_NAME)

install-operator: install-catalog-source ## Install the operator from catalog source
	- kubectl apply -f config/samples/subscription.yaml 

uninstall-operator: uninstall-catalog-source ## Install the operator from catalog source
	- kubectl get csv -o name | grep ibm-crossplane | xargs kubectl delete
	- kubectl delete --ignore-not-found -f config/samples/subscription.yaml
	- make clean-cluster

clean-cluster: ## Clean up all the resources left in the Kubernetes cluster
	@echo ....... Cleaning up .......
	- kubectl get crossplanes -o name | xargs kubectl delete
	- kubectl get csv -o name | grep ibm-crossplane | xargs kubectl delete
	- kubectl get sub -o name | grep ibm-crossplane | xargs kubectl delete
	- kubectl get installplans | grep ibm-crossplane | awk '{print $$1}' | xargs kubectl delete installplan
	- kubectl get serviceaccounts -o name | grep ibm-crossplane | xargs kubectl delete
	- kubectl get configurationrevisions -o name | xargs kubectl patch -p '{"metadata":{"finalizers": []}}' --type=merge
	- kubectl get configurationrevisions -o name | xargs kubectl delete
	- kubectl get compositeresourcedefinitions -o name | xargs kubectl patch -p '{"metadata":{"finalizers": []}}' --type=merge
	- kubectl get compositeresourcedefinitions -o name | xargs kubectl delete
	- kubectl get configurations -o name --ignore-not-found | xargs kubectl delete
	- kubectl patch locks lock -p '{"metadata":{"finalizers": []}}' --type=merge
	- kubectl get crds,clusterroles,clusterrolebindings -o name | grep crossplane | xargs kubectl delete --ignore-not-found
	- kubectl -n openshift-marketplace get jobs -o name | xargs kubectl -n openshift-marketplace delete --ignore-not-found

create-secret: ## Create artifactory secret in current namespace
	kubectl create secret docker-registry artifactory-secret --docker-server=$(ARTIFACTORY_REGISTRY) --docker-username=$(ARTIFACTORY_USER) --docker-password=$(ARTIFACTORY_TOKEN) --docker-email=none

delete-secret: ## Delete artifactory secret from current namespace
	kubectl delete secret artifactory-secret --ignore-not-found=true

global-pull-secrets: ## Update global pull secrets to use artifactory registries
	./common/scripts/update_global_pull_secrets.sh

############################################################
##@ Test
############################################################

test: ## Run unit test on prow
	@echo good

############################################################
##@ Build
############################################################

build: build-image-amd64 build-image-ppc64le build-image-s390x  ## Build operator images

build-dev: build-image-dev ## Build operator image for development

build-catalog: build-bundle-image build-catalog-source ## Build bundle image and catalog source image for development

# Build bundle image
build-bundle-image: bundle
	@cp -f bundle/manifests/ibm-crossplane-operator.clusterserviceversion.yaml /tmp/ibm-crossplane-operator.clusterserviceversion.yaml
	@$(YQ) d -i bundle/manifests/ibm-crossplane-operator.clusterserviceversion.yaml "spec.replaces"
	sed -i -e "s|quay.io/opencloudio|$(REGISTRY)|g" bundle/manifests/ibm-crossplane-operator.clusterserviceversion.yaml
	$(CONTAINER_CLI) $(CONTAINER_BUILD_CMD) -f bundle.Dockerfile -t $(REGISTRY)/$(BUNDLE_IMAGE_NAME):$(VERSION)-$(ARCH) .
	$(CONTAINER_CLI) push $(REGISTRY)/$(BUNDLE_IMAGE_NAME):$(VERSION)-$(ARCH)
	@mv /tmp/ibm-crossplane-operator.clusterserviceversion.yaml bundle/manifests/ibm-crossplane-operator.clusterserviceversion.yaml

# Build catalog source
build-catalog-source:
	$(OPM) -u $(CONTAINER_CLI) index add --bundles $(REGISTRY)/$(BUNDLE_IMAGE_NAME):$(VERSION)-$(ARCH) --tag $(REGISTRY)/$(OPERATOR_IMAGE_NAME)-catalog:$(VERSION)
	$(CONTAINER_CLI) push $(REGISTRY)/$(OPERATOR_IMAGE_NAME)-catalog:$(VERSION)

# Build image for development
build-image-dev: update-submodule
	$(CONTAINER_CLI) $(CONTAINER_BUILD_CMD) -t $(REGISTRY)/$(OPERATOR_IMAGE_NAME):dev \
	--build-arg VCS_REF=$(VCS_REF) --build-arg VCS_URL=$(VCS_URL) --build-arg PLATFORM=linux_$(ARCH) \
	-f Dockerfile .

push-image-dev:
	$(CONTAINER_CLI) push $(REGISTRY)/$(OPERATOR_IMAGE_NAME):dev

# Build image for amd64
build-image-amd64: buildx $(CONFIG_DOCKER_TARGET) update-submodule
ifneq ($(ARCH),amd64)
	$(eval CONTAINER_BUILD_CMD = build --push --platform linux/amd64)
ifeq (,$(BUILDX))
	$(eval CONTAINER_CLI = $(BUILDX_PLUGIN))
else
	$(eval CONTAINER_CLI = docker buildx)
endif
endif
	$(CONTAINER_CLI) $(CONTAINER_BUILD_CMD) -t $(OPERATOR_IMAGE)-amd64 -t $(OPERATOR_IMAGE)-$(GIT_VERSION)-amd64 \
	--build-arg VCS_REF=$(VCS_REF) --build-arg VCS_URL=$(VCS_URL) --build-arg PLATFORM=linux_amd64 \
	-f Dockerfile .

push-image-amd64:
ifeq ($(ARCH),amd64)
	$(CONTAINER_CLI) push $(OPERATOR_IMAGE)-amd64
	$(CONTAINER_CLI) push $(OPERATOR_IMAGE)-$(GIT_VERSION)-amd64
endif


# Build image for ppc64le
build-image-ppc64le: buildx $(CONFIG_DOCKER_TARGET) update-submodule
ifneq ($(ARCH),ppc64le)
	$(eval CONTAINER_BUILD_CMD = build --push --platform linux/ppc64le)
ifeq (,$(BUILDX))
	$(eval CONTAINER_CLI = $(BUILDX_PLUGIN))
else
	$(eval CONTAINER_CLI = docker buildx)
endif
endif
	$(CONTAINER_CLI) $(CONTAINER_BUILD_CMD) -t $(OPERATOR_IMAGE)-ppc64le -t $(OPERATOR_IMAGE)-$(GIT_VERSION)-ppc64le \
	--build-arg VCS_REF=$(VCS_REF) --build-arg VCS_URL=$(VCS_URL) --build-arg PLATFORM=linux_ppc64le \
	-f Dockerfile .

push-image-ppc64le:
ifeq ($(ARCH),ppc64le)
	$(CONTAINER_CLI) push $(OPERATOR_IMAGE)-ppc64le
	$(CONTAINER_CLI) push $(OPERATOR_IMAGE)-$(GIT_VERSION)-ppc64le
endif

# Build image for s390x
build-image-s390x: buildx $(CONFIG_DOCKER_TARGET) update-submodule
ifneq ($(ARCH),s390x)
	$(eval CONTAINER_BUILD_CMD = build --push --platform linux/s390x)
ifeq (,$(BUILDX))
	$(eval CONTAINER_CLI = $(BUILDX_PLUGIN))
else
	$(eval CONTAINER_CLI = docker buildx)
endif
endif
	$(CONTAINER_CLI) $(CONTAINER_BUILD_CMD) -t $(OPERATOR_IMAGE)-s390x -t $(OPERATOR_IMAGE)-$(GIT_VERSION)-s390x \
	--build-arg VCS_REF=$(VCS_REF) --build-arg VCS_URL=$(VCS_URL) --build-arg PLATFORM=linux_s390x \
	-f Dockerfile .

push-image-s390x:
ifeq ($(ARCH),s390x)
	$(CONTAINER_CLI) push $(OPERATOR_IMAGE)-s390x
	$(CONTAINER_CLI) push $(OPERATOR_IMAGE)-$(GIT_VERSION)-s390x
endif

# Build binary in ibm-crossplane submodule
build-crossplane-binary:
	rm -rf ibm-crossplane/_output/bin/*
	make -C ibm-crossplane build.all
	
############################################################
##@ Release
############################################################

update-submodule:
	make copy-operator-data
	make build-crossplane-binary

add-services-files: ## Copy services crd and rbac files.
	cp ./services/*/crd/* ./config/crd/bases/
	(cd ./config/crd; $(KUSTOMIZE) edit add resource ./bases/*)
	cp ./services/*/rbac/* ./config/rbac
	(cd ./config/rbac; find . -type f  | grep -v kustomization | xargs $(KUSTOMIZE) edit add resource)

copy-operator-data: ## Copy files from ibm-crossplane submodule before recreating bundle
#	git submodule update --init --recursive
	cp ibm-crossplane/cluster/crds/* config/crd/bases/
	- make add-services-files

bundle: kustomize copy-operator-data ## Generate bundle manifests and metadata, then validate the generated files
	$(OPERATOR_SDK) generate kustomize manifests -q
	- make bundle-manifests CHANNELS=v3 DEFAULT_CHANNEL=v3

bundle-manifests:
	$(KUSTOMIZE) build config/manifests | $(OPERATOR_SDK) generate bundle \
	-q --overwrite --version $(VERSION) $(BUNDLE_METADATA_OPTS)
	$(OPERATOR_SDK) bundle validate ./bundle
	@./common/scripts/adjust_manifests.sh $(VERSION) $(PREVIOUS_VERSION)

images: build-image-amd64 push-image-amd64 build-image-ppc64le push-image-ppc64le build-image-s390x push-image-s390x ## Build and publish the multi-arch operator image
ifeq ($(OS),$(filter $(OS),linux darwin))
	curl -L -o /tmp/manifest-tool https://github.com/estesp/manifest-tool/releases/download/v1.0.3/manifest-tool-$(OS)-$(ARCH)
	chmod +x /tmp/manifest-tool
	@echo "Merging and push multi-arch image $(REGISTRY)/$(OPERATOR_IMAGE_NAME):latest"
	/tmp/manifest-tool $(MANIFEST_TOOL_ARGS) push from-args --platforms linux/amd64 --template $(REGISTRY)/$(OPERATOR_IMAGE_NAME):$(VERSION)-$(GIT_VERSION)-ARCH --target $(REGISTRY)/$(OPERATOR_IMAGE_NAME):latest
	@echo "Merging and push multi-arch image $(REGISTRY)/$(OPERATOR_IMAGE_NAME):$(VERSION)"
	/tmp/manifest-tool $(MANIFEST_TOOL_ARGS) push from-args --platforms linux/amd64 --template $(REGISTRY)/$(OPERATOR_IMAGE_NAME):$(VERSION)-$(GIT_VERSION)-ARCH --target $(REGISTRY)/$(OPERATOR_IMAGE_NAME):$(VERSION)
	@echo "Merging and push multi-arch image $(REGISTRY)/$(OPERATOR_IMAGE_NAME):$(VERSION)-$(GIT_VERSION)"
	/tmp/manifest-tool $(MANIFEST_TOOL_ARGS) push from-args --platforms linux/amd64 --template $(REGISTRY)/$(OPERATOR_IMAGE_NAME):$(VERSION)-$(GIT_VERSION)-ARCH --target $(REGISTRY)/$(OPERATOR_IMAGE_NAME):$(VERSION)-$(GIT_VERSION)
	@echo "Merging and push multi-arch image $(REGISTRY)/$(OPERATOR_IMAGE_NAME):latest"
	/tmp/manifest-tool $(MANIFEST_TOOL_ARGS) push from-args --platforms linux/amd64,linux/ppc64le,linux/s390x --template $(REGISTRY)/$(OPERATOR_IMAGE_NAME):$(VERSION)-$(GIT_VERSION)-ARCH --target $(REGISTRY)/$(OPERATOR_IMAGE_NAME):latest
	@echo "Merging and push multi-arch image $(REGISTRY)/$(OPERATOR_IMAGE_NAME):$(VERSION)"
	/tmp/manifest-tool $(MANIFEST_TOOL_ARGS) push from-args --platforms linux/amd64,linux/ppc64le,linux/s390x --template $(REGISTRY)/$(OPERATOR_IMAGE_NAME):$(VERSION)-$(GIT_VERSION)-ARCH --target $(REGISTRY)/$(OPERATOR_IMAGE_NAME):$(VERSION)
	@echo "Merging and push multi-arch image $(REGISTRY)/$(OPERATOR_IMAGE_NAME):$(VERSION)-$(GIT_VERSION)"
	/tmp/manifest-tool $(MANIFEST_TOOL_ARGS) push from-args --platforms linux/amd64,linux/ppc64le,linux/s390x --template $(REGISTRY)/$(OPERATOR_IMAGE_NAME):$(VERSION)-$(GIT_VERSION)-ARCH --target $(REGISTRY)/$(OPERATOR_IMAGE_NAME):$(VERSION)-$(GIT_VERSION)
endif



############################################################
##@ Help
############################################################
help: ## Display this help
	@echo "Usage:\n  make \033[36m<target>\033[0m"
	@awk 'BEGIN {FS = ":.*##"}; \
		/^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
