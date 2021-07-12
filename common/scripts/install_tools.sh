#! /usr/bin/env bash
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

export OS_NAME=$(uname -s)
export ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    export LOCAL_ARCH="amd64"
else
    export LOCAL_ARCH="$ARCH"
fi

export TOOLS_DIR="$(pwd)/bin"
if [[ ! -d "$TOOLS_DIR" ]]; then
    mkdir "$TOOLS_DIR"
fi


function check_yq() {
    if [[ $(which yq) != "" ]]; then
        YQ=$(which yq)
    elif [[ ! -f "$TOOLS_DIR/yq" ]]; then
        make yq
    fi
    export YQ=${YQ:-"$TOOLS_DIR/yq"}
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
        local OS="linux"
        if [[ $OS_NAME == "Darwin" ]]; then
            OS="darwin"
        fi
        echo "istalling operator-sdk"
        local RELEASE_VERSION="v1.4.2"
        local URL="https://github.com/operator-framework/operator-sdk/releases/download"
        local FILE_NAME="operator-sdk_${OS}_${LOCAL_ARCH}"
        $CURL -LO "$URL/$RELEASE_VERSION/$FILE_NAME"
        chmod +x "$FILE_NAME"
        cp "$FILE_NAME" "$TOOLS_DIR/operator-sdk"
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

function check_container_cli() {
    if [[ $(which docker) != "" ]]; then
        export CONTAINER_CLI=$(which docker)
    else
        echo "no docker executable in \$PATH"
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

check_container_cli
check_curl
check_operator_sdk
check_kustomize
check_opm
check_yq
export TOOLS_CHECKED=true
