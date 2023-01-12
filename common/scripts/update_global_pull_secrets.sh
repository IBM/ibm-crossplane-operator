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

# checking ARTIFACTORY_USER
if [ -z "${ARTIFACTORY_USER}" ]; then
    echo "[ERROR] Environment variable ARTIFACTORY_USER not defined"
    exit 1
fi

# checking ARTIFACTORY_TOKEN
if [ -z "${ARTIFACTORY_TOKEN}" ]; then
    echo "[ERROR] Environment variable ARTIFACTORY_TOKEN not defined"
    exit 1
fi

changed=false
artifactory_secret=$(echo -n "${ARTIFACTORY_USER}:${ARTIFACTORY_TOKEN}" | base64 | tr -d "\r|\n| ")
new_pull_secret=$(kubectl -n openshift-config get secret/pull-secret -o jsonpath='{.data.\.dockerconfigjson}' | base64 --decode | tr -d "\r|\n| ")

if [[ -z "$(echo "${new_pull_secret}" | grep 'hyc-cloud-private-scratch-docker-local')" ]]; then
    registry_pull_secret="\"hyc-cloud-private-scratch-docker-local.artifactory.swg-devops.com\":{\"auth\":\"${artifactory_secret}\"}"
    new_pull_secret=$(echo "${new_pull_secret}" | sed -e "s/}}$//")
    new_pull_secret=$(echo "${new_pull_secret},${registry_pull_secret}}}")
    changed=true
fi

if [[ -z "$(echo "${new_pull_secret}" | grep 'hyc-cloud-private-integration-docker-local')" ]]; then
    registry_pull_secret="\"hyc-cloud-private-integration-docker-local.artifactory.swg-devops.com\":{\"auth\":\"${artifactory_secret}\"}"
    new_pull_secret=$(echo "${new_pull_secret}" | sed -e "s/}}$//")
    new_pull_secret=$(echo "${new_pull_secret},${registry_pull_secret}}}")
    changed=true
fi

if [[ -z "$(echo "${new_pull_secret}"| grep 'hyc-cloud-private-daily-docker-local')" ]]; then
    registry_pull_secret="\"hyc-cloud-private-daily-docker-local.artifactory.swg-devops.com\":{\"auth\":\"${artifactory_secret}\"}"
    new_pull_secret=$(echo "${new_pull_secret}" | sed -e "s/}}$//")
    new_pull_secret=$(echo "${new_pull_secret},${registry_pull_secret}}}")
    changed=true
fi

if [[ -z "$(echo "${new_pull_secret}" | grep 'hyc-cloud-private-edge-docker-local')" ]]; then
    registry_pull_secret="\"hyc-cloud-private-edge-docker-local.artifactory.swg-devops.com\":{\"auth\":\"${artifactory_secret}\"}"
    new_pull_secret=$(echo "${new_pull_secret}" | sed -e "s/}}$//")
    new_pull_secret=$(echo "${new_pull_secret},${registry_pull_secret}}}")
    changed=true
fi

if [[ "${changed}" == "true" ]]; then
    echo "${new_pull_secret}" > /tmp/dockerconfig.json
    oc -n openshift-config set data secret/pull-secret --from-file=.dockerconfigjson=/tmp/dockerconfig.json

    if [[ "$?" -ne 0 ]]; then
        echo "[ERROR] Error updating global pull secrets"
        exit 1
    else
        echo "[INFO] Global pull secrets updated. It will take effect after each node is restarted"
    fi
else
    echo "[INFO] No change"
fi