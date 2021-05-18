#!/bin/bash
#
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
#

OPERATOR_VERSION=$1
PREVIOUS_VERSION=$2
OPERATOR_NAME=ibm-crossplane-operator
BUNDLE_DOCKERFILE_PATH=bundle.Dockerfile
BUNDLE_ANNOTATIONS_PATH=bundle/metadata/annotations.yaml
OPERANDREQUEST_PATH=config/manifests/operandrequest.json
CSV_PATH=bundle/manifests/ibm-crossplane-operator.clusterserviceversion.yaml
CHART_PATH=helm-charts/ibm-crossplane/Chart.yaml

if [[ -z "${OPERATOR_VERSION}" || -z "${PREVIOUS_VERSION}" ]]; then
    echo "Usage: $0 OPERATOR_VERSION PREVIOUS_VERSION"
    exit 1
fi

# adjust bundle.Dockerfile
if [[ -f "${BUNDLE_DOCKERFILE_PATH}" ]]; then
    echo "[INFO] Adjusting ${BUNDLE_DOCKERFILE_PATH}"
    cat ${BUNDLE_DOCKERFILE_PATH} | sed -e "s|package.v1=${OPERATOR_NAME}$|package.v1=${OPERATOR_NAME}-app|" 1<>${BUNDLE_DOCKERFILE_PATH} 
fi

# adjust annotations.yaml
if [[ -f "${BUNDLE_ANNOTATIONS_PATH}" ]]; then
    echo "[INFO] Adjusting ${BUNDLE_ANNOTATIONS_PATH}"
    cat ${BUNDLE_ANNOTATIONS_PATH} | sed -e "s|package.v1: ${OPERATOR_NAME}$|package.v1: ${OPERATOR_NAME}-app|" 1<>${BUNDLE_ANNOTATIONS_PATH}
fi

# adjust csv
if [[ -f "${CSV_PATH}" ]]; then
    echo "[INFO] Adjusting ${CSV_PATH}"

    # alm-examples
    # NEW_AL_EXAMPLES_JSON=$(yq r ${CSV_PATH} metadata.annotations.alm-examples | jq ".[.|length] |= . + $(cat ${OPERANDREQUEST_PATH})")
    # yq w ${CSV_PATH} "metadata.annotations.alm-examples" "${NEW_AL_EXAMPLES_JSON}" 1<>${CSV_PATH}

    # olm.skipRange
    yq w ${CSV_PATH} "metadata.annotations[olm.skipRange]" ">=1.0.0 <${OPERATOR_VERSION}" 1<>${CSV_PATH}

    # replaces
    # yq w ${CSV_PATH} "spec.replaces" "${OPERATOR_NAME}.v${PREVIOUS_VERSION}" 1<>${CSV_PATH}
    # yq d -i ${CSV_PATH} "spec.replaces" # temporary adjustment for moving to v3 channel
fi

# adjust Chart.yaml
if [[ -f "${CHART_PATH}" ]]; then
    echo "[INFO] Adjusting ${CHART_PATH}"

    # version
    yq w ${CHART_PATH} version "${OPERATOR_VERSION}" 1<>${CHART_PATH}
fi