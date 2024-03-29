#!/bin/bash
#
# Copyright 2023 IBM Corporation
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

STATUS=0
ARCH=$(uname -m)
[[ "${ARCH}" != "x86_64" ]] && exit 0

JQ=$(command -v jq)
YQ=$(command -v yq)

if [[ "X${JQ}" == "X" ]]; then
    curl -L -o /tmp/jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
    chmod +x /tmp/jq
    JQ=/tmp/jq
fi
if [[ "X${YQ}" == "X" ]]; then
    curl -L -o /tmp/yq https://github.com/mikefarah/yq/releases/download/3.3.0/yq_linux_amd64
    chmod +x /tmp/yq
    YQ=/tmp/yq
fi

CSV_PATH=bundle/manifests/ibm-crossplane-operator.clusterserviceversion.yaml

# Lint alm-examples
echo "==> Linting ${CSV_PATH}"
${YQ} v ${CSV_PATH} || exit 1

$(${YQ} r ${CSV_PATH} metadata.annotations.alm-examples | ${JQ} '. | length == 10') == "true" || STATUS=1

if [[ ${STATUS} -eq 1 ]]; then
    echo "[ERROR] Incomplete alm-examples"
    exit ${STATUS}
fi
