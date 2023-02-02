#! /usr/bin/env bash
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

if [[ $(uname -s) == "Darwin" ]]; then
    export OS="darwin"
else
    export OS="linux"
fi
export ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    export ARCH="amd64"
else
    export ARCH="$ARCH"
fi

export TOOLS_DIR="$(pwd)/bin"
if [[ ! -d "$TOOLS_DIR" ]]; then
    mkdir "$TOOLS_DIR"
fi

function check_yq() {
    local RELEASE_VERSION="3.4.1"
    local URL="https://github.com/mikefarah/yq/releases/download"
    local FILE_NAME="yq_${OS}_${ARCH}"
    $CURL -L -o "$TOOLS_DIR/yq" "$URL/$RELEASE_VERSION/$FILE_NAME"
    chmod +x "$TOOLS_DIR/yq"
    export YQ="$TOOLS_DIR/yq"
    $YQ --version
}

function check_kustomize() {
    if [[ $(which kustomize) != "" ]]; then
        KUSTOMIZE=$(which kustomize)
    elif [[ ! -f "$TOOLS_DIR/kustomize" ]]; then
        make kustomize
    fi
    export KUSTOMIZE=${KUSTOMIZE:-"$TOOLS_DIR/kustomize"}
    echo -n "kustomize " && $KUSTOMIZE version
}

function check_operator_sdk() {
    if [[ $(which operator-sdk) != "" ]]; then
        OPERATOR_SDK=$(which operator-sdk)
    elif [[ ! -f "$TOOLS_DIR/operator-sdk" ]]; then
        local RELEASE_VERSION="v1.3.0"
        local URL="https://github.com/operator-framework/operator-sdk/releases/download"
        local FILE_NAME="operator-sdk_${OS}_${ARCH}"
        $CURL -L -o "$TOOLS_DIR/operator-sdk" "$URL/$RELEASE_VERSION/$FILE_NAME"
        chmod +x "$TOOLS_DIR/operator-sdk"
        echo "done"
    fi
    export OPERATOR_SDK=${OPERATOR_SDK:-"$TOOLS_DIR/operator-sdk"}
    $OPERATOR_SDK version | cut -f1 -d,
}

function check_opm() {
    if [[ $(which opm) != "" ]]; then
        OPM=$(which opm)
    elif [[ ! -f "$TOOLS_DIR/opm" ]]; then
        make opm
    fi
    export OPM=${OPM:-"$TOOLS_DIR/opm"}
    echo -n "opm version: " && $OPM version | cut -f2 -d\"
}

function check_manifest_tool() {
    if [[ $(which manifest-tool) != "" ]]; then
        export MANIFEST_TOOL=$(which manifest-tool)
    elif [[ ! -f "$TOOLS_DIR/manifest-tool" ]]; then
        local RELEASE_VERSION="v1.0.3"
        local URL="https://github.com/estesp/manifest-tool/releases/download"
        local FILE_NAME="manifest-tool-${OS}-${ARCH}"
        $CURL -L -o "$TOOLS_DIR/manifest-tool" "$URL/$RELEASE_VERSION/$FILE_NAME"
	    chmod +x "$TOOLS_DIR/manifest-tool"
	fi
    export MANIFEST_TOOL=${MANIFEST_TOOL:-"$TOOLS_DIR/manifest-tool"}
    $MANIFEST_TOOL --version
}

function check_container_cli() {
    if [[ $(which docker) != "" ]]; then
        export CONTAINER_CLI="docker"
    elif [[ $(which podman) != "" ]]; then
        export CONTAINER_CLI="podman"
        export CONTAINER_FORMAT="--format docker"
    else
        echo "no podman/docker executable in \$PATH"
        exit 1
    fi
    $CONTAINER_CLI --version
}

function check_curl() {
    if [[ $(which curl) != "" ]]; then
        export CURL="$(which curl) -s"
    else
        echo "no curl executable in \$PATH"
        exit 1
    fi
    echo -n "curl version: " && $CURL --version | grep "^curl" | cut -f2 -d' '
}

check_curl
check_container_cli
check_manifest_tool
check_operator_sdk
check_kustomize
check_opm
check_yq
export TOOLS_CHECKED=true
