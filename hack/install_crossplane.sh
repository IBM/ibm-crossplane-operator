#!/usr/bin/env bash
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

if [[ (-z "${ARTIFACTORY_REPO}") ]]; then
    ARTIFACTORY_REPO=integration
fi
if [[ (-z "${ARTIFACTORY_URL}") ]]; then
    ARTIFACTORY_URL="hyc-cloud-private-${ARTIFACTORY_REPO}-docker-local.artifactory.swg-devops.com"
fi
echo "[INFO] ARTIFACTORY_URL set to ${ARTIFACTORY_URL}"

if [[ (-z "${ARTIFACTORY_TOKEN}" || -z "${ARTIFACTORY_USER}") ]]; then
    echo "[ERROR] set env variable ARTIFACTORY_TOKEN and ARTIFACTORY_USER"
    exit 1
fi
echo "[INFO] ARTIFACTORY_TOKEN and ARTIFACTORY_USER set"

if [[ (-z "${INSTALL_NAMESPACE}") ]]; then
    INSTALL_NAMESPACE="ibm-common-services"
fi
echo "[INFO] INSTALL_NAMESPACE set to ${INSTALL_NAMESPACE}"

echo "[INFO] create secret with artifactory credentials"
kubectl -n "${INSTALL_NAMESPACE}" create secret docker-registry "artifactory-${ARTIFACTORY_REPO}"\
  --docker-server="${ARTIFACTORY_URL}" \
  --docker-username="${ARTIFACTORY_USER}" \
  --docker-password="${ARTIFACTORY_TOKEN}" \
  --docker-email=none

echo "[INFO] create ibm-crossplane ServiceAccount"
CROSSPLANE_NAME="ibm-crossplane"
kubectl -n "${INSTALL_NAMESPACE}" create sa "${CROSSPLANE_NAME}"
kubectl -n "${INSTALL_NAMESPACE}" patch serviceaccount "${CROSSPLANE_NAME}" \
  -p "{\"imagePullSecrets\": [{\"name\": \"artifactory-${ARTIFACTORY_REPO}\"}]}"

echo "[INFO] apply crossplane's CRDs"
kubectl apply -f ./config/crd/bases

echo "[INFO] apply crossplane's RBAC resources"
kubectl -n "${INSTALL_NAMESPACE}" apply -f ./config/rbac

echo "[INFO] create crossplane's deployment"
if yq --version | grep -q 'version 4'; then
  echo "[INFO] detected yq version 4"
  sed  "s|icr.io/cpopen/cpfs|${ARTIFACTORY_URL}/ibmcom|g" config/manager/manager.yaml |\
  sed  "s|icr.io/cpopen|${ARTIFACTORY_URL}/ibmcom|g" config/manager/manager.yaml |\
    yq e ".spec.template.metadata.annotations[\"olm.targetNamespaces\"] = \"${INSTALL_NAMESPACE}\"" - |\
    kubectl -n "${INSTALL_NAMESPACE}" apply -f -
else
  echo "[INFO] detected yq version 3"
  sed  "s|icr.io/cpopen/cpfs|${ARTIFACTORY_URL}/ibmcom|g" config/manager/manager.yaml |\
  sed  "s|icr.io/cpopen|${ARTIFACTORY_URL}/ibmcom|g" config/manager/manager.yaml |\
    yq w - "spec.template.metadata.annotations[olm.targetNamespaces]" "${INSTALL_NAMESPACE}" |\
    kubectl -n "${INSTALL_NAMESPACE}" apply -f -
fi

echo "[INFO] create Configuration"
cat <<EOF | kubectl apply -f -
apiVersion: pkg.ibm.crossplane.io/v1
kind: Configuration
metadata:
  name: ibm-crossplane-bedrock-shim-config
  labels:
    ibm-crossplane-provider: ibmcloud
spec:
  ignoreCrossplaneConstraints: false
  package: FromEnvVar
  packagePullSecrets:
    - name: artifactory-${ARTIFACTORY_REPO}
  packagePullPolicy: Always
  revisionActivationPolicy: Automatic
  revisionHistoryLimit: 1
  skipDependencyResolution: false
EOF
