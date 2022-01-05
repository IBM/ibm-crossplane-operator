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
############################################################
#### Helper functions
############################################################

SCRIPT_NAME=$(basename $0)
# text colours
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

TIMESTAMP=$(date +%s)
SCRATCH_REG="hyc-cloud-private-scratch-docker-local.artifactory.swg-devops.com/ibmcom"
REGISTRY=${REGISTRY:-"$SCRATCH_REG"}

# usage: info <message>;
function info() {
    if [ -t 1 ]; then
        echo -e "${GREEN}[INFO]${NC} $SCRIPT_NAME: $1"
    else
        echo -e "[INFO] $SCRIPT_NAME: $1"
    fi
}

# usage: erro <message>;
function erro() {
    if [ -t 1 ]; then
        echo -e "${RED}[ERROR]${NC} $SCRIPT_NAME: $1"
    else
        echo -e "[ERROR] $SCRIPT_NAME: $1"
    fi
    print_usage
    cleanup 1
}

# usage: print_usage;
function print_usage() {
    echo -e "Usage: $SCRIPT_NAME [-h] | [-t TAG] 

Build catalog source with ibm-crossplane-operator

Options:
 -h  | --help 
        Show this message
 -f  | --force
        Force build of image even if no changes are detected
 -t  | --tag TAG 
        Build ibm-crossplane-operator-bundle and ibm-common-service-catalog with TAG
 -r  | --registry REGISTRY
        Registry for final catsrc image (also can be changed by setting env variable REGISTRY)
 -ac | --artifactory-creds USER:TOKEN
        Credentials for 'docker login' (by default sourced from 
        variables ARTIFACTORY_USER and ARTIFACTORY_TOKEN)
 -ot | --operand-tags OPERAND_TAG_LIST
        Build crossplane operator bundle with operand images with tags specified
        in OPERAND_TAG_LIST in format \"OPERAND_1:TAG_1:REG_1,...,OPERAND_N:TAG_N:REG_N\",
        default for every image are contents of file \"RELEASE_VERSION\"
 -b  | --bundles BUNDLE_LIST
        List of bundles to be added to catalog in format \"BUNDLE_IMAGE_1,...,BUNDLE_IMAGE_N\"
"
}

# usage: setup;
function setup() {
    set -e
    START_WD=$(pwd)
    if [[ "$TOOLS_CHECKED" != true ]]; then
        info "checking tools..."
        source common/scripts/install_tools.sh
        info "done"
    fi
    if [[ "$ARTIFACTORY_USER" != "" && "$ARTIFACTORY_TOKEN" != "" ]]; then
        info "log in to container registry"
        echo "$ARTIFACTORY_TOKEN" | $CONTAINER_CLI login "$SCRATCH_REG" -u "$ARTIFACTORY_USER" --password-stdin
        echo "$ARTIFACTORY_TOKEN" | $CONTAINER_CLI login "$COMMON_SERVICE_BASE_REGISTRY" -u "$ARTIFACTORY_USER" --password-stdin
    else
        erro "ARTIFACTORY_USER or ARTIFACTORY_TOKEN not set"
    fi
    if [[ $(uname -s) == "Darwin" ]]; then
        export MANIFEST_TOOL="$MANIFEST_TOOL --username $ARTIFACTORY_USER --password $ARTIFACTORY_TOKEN"
    fi
    RELEASE_VERSION=$(cat RELEASE_VERSION)
    CROSSPLANE_BRANCH=$(git branch --show-current)
    TEMP_WD=$(mktemp -d)
    START_WD=$(pwd)
    info "temp dir: $TEMP_WD"
    cp -R . "$TEMP_WD"
    cd "$TEMP_WD"
}

# usage: cleanup <exit code>;
function cleanup() {
    info "cleaning up"
    cd "$START_WD"
    exit $1
}

# usage: build_multiarch <dockerfile> <tags array>;
function build_multiarch() {
    local DOCKERFILE="$1"
    shift
    local TAGS=("$@")
    local ARCHS=(amd64 ppc64le s390x)
    local PLATFORMS="linux/amd64,linux/ppc64le,linux/s390x"
    if [[ $CONTAINER_CLI == "podman" ]]; then
        for ARCH in "${ARCHS[@]}"; do
            local BUILD_ARGS="--arch $ARCH"
            $CONTAINER_CLI build $CONTAINER_FORMAT $BUILD_ARGS -f $DOCKERFILE -t $TAGS-$ARCH .
            $CONTAINER_CLI push $TAGS-$ARCH
        done
        for TAG in "${TAGS[@]}"; do
            $MANIFEST_TOOL push from-args \
                --platforms "$PLATFORMS" \
                --template "$TAGS-ARCH" \
                --target "$TAG"
        done
    elif [[ $CONTAINER_CLI == "docker" ]]; then
        for TAG in "${TAGS[@]}"; do
            local TAG_LIST="$TAG_LIST -t $TAG"
        done
        $CONTAINER_CLI buildx build --platform $PLATFORMS -f $DOCKERFILE $TAG_LIST . --push
    fi
}

############################################################
#### Operator bundle functions
############################################################

declare -A IMG_TAGS
declare -A IMG_REGS
declare -A IMG_NAMES
declare -A IMAGES

OPERATOR_NAME="ibm-crossplane-operator"
OPERATOR_IMG="ibm-crossplane-operator"
IBM_BEDROCK_SHIM_IMG="ibm-crossplane-bedrock-shim-config"
IMG_NAMES=([$OPERATOR_IMG]="scratch" [$IBM_BEDROCK_SHIM_IMG]="integration")
BUNDLE_METADATA_OPTS="--channels=v3 --default-channel=v3"
OPERATOR_BUNDLE="ibm-crossplane-operator-bundle"
OPERATOR_BUNDLE_IMG="$SCRATCH_REG/$OPERATOR_BUNDLE:$TIMESTAMP"

# usage: set_image_digest <image name> <image tag> <image registry>;
function set_image_digest() {
    local NAME=$1
    local TAG=$2
    local REG=$3
    local REGISTRY_URI="hyc-cloud-private-$REG-docker-local.artifactory.swg-devops.com/ibmcom"
    local REGISTRY_URL="https://na.artifactory.swg-devops.com/artifactory/hyc-cloud-private-$REG-docker-local/ibmcom"
    info "getting digest for $NAME:$TAG:$REG"
    local DIGEST=$($CURL --user "$ARTIFACTORY_USER:$ARTIFACTORY_TOKEN" \
        "$REGISTRY_URL/$NAME/$TAG/list.manifest.json?properties" |
        grep "docker.manifest.digest" | cut -f4 -d\")
    if [[ $DIGEST == "" ]]; then
        DIGEST=$($CURL --user "$ARTIFACTORY_USER:$ARTIFACTORY_TOKEN" \
            "$REGISTRY_URL/$NAME/$TAG/manifest.json?properties" |
            grep "docker.manifest.digest" | cut -f4 -d\")
        if [[ $DIGEST == "" ]]; then
            erro "could not find digest for $REGISTRY_URI/$NAME:$TAG"
        fi
    fi
    info "digest of $NAME:$TAG:$REG: $DIGEST"
    IMAGES["$NAME"]="$REGISTRY_URI/$NAME@$DIGEST"
}

# usage: set_image_digests;
function set_image_digests() {
    info "downloading image digests..."
    for IMG in "${!IMG_NAMES[@]}"; do
        local TAG="${IMG_TAGS[$IMG]}"
        local REG="${IMG_REGS[$IMG]}"
        set_image_digest "$IMG" "$TAG" "$REG"
    done
    info "done"
}

# usage: check_image_digests;
function check_image_digests() {
    local OLD_CUSTOM_CATSRC=${CATSRC_TAGS[0]}
    local REG=$(echo $OLD_CUSTOM_CATSRC | cut -f1 -d.)
    local SUB_REG=$(echo $OLD_CUSTOM_CATSRC | cut -f2 -d/)
    local IMG=$(echo $OLD_CUSTOM_CATSRC | cut -f3 -d/ | cut -f1 -d:)
    local TAG=$(echo $OLD_CUSTOM_CATSRC | cut -f2 -d:)
    local URL="https://na.artifactory.swg-devops.com/artifactory/$REG/$SUB_REG/$IMG/$TAG"
    local RESP=$($CURL --user "$ARTIFACTORY_USER:$ARTIFACTORY_TOKEN" "$URL")
    if [[ $RESP == "" ]]; then
        local CHANGED=false
        info "pulling previous image with tag ${CATSRC_TAGS[0]}"
        $CONTAINER_CLI pull $OLD_CUSTOM_CATSRC
        info "looking for changes in images.."
        for IMG in "${!IMG_NAMES[@]}"; do
            local FORMAT="'{{index .Config.Labels \"$IMG\"}}'"
            local OLD_IMG=$(echo "$CONTAINER_CLI inspect --format=$FORMAT $OLD_CUSTOM_CATSRC" | sh)
            local NEW_IMG="${IMAGES[$IMG]}"
            info "old $IMG: $OLD_IMG"
            info "new $IMG: $NEW_IMG"
            if [[ "$OLD_IMG" != "$NEW_IMG" ]]; then
                CHANGED=true
            fi
        done
        if [[ "$CHANGED" == false ]]; then
            info "no changes in images"
            cleanup 0
        fi
    fi
}

# usage: prepare_operator_bundle_yamls;
function prepare_operator_bundle_yamls() {
    local MANIFEST_CSV_YAML="./config/manifests/bases/$OPERATOR_IMG.clusterserviceversion.yaml"
    local CSV_YAML="./bundle/manifests/$OPERATOR_IMG.clusterserviceversion.yaml"
    local METADATA_YAML="./bundle/metadata/annotations.yaml"
    # manifests
    $YQ w -i "$MANIFEST_CSV_YAML" "metadata.annotations.\"olm.skipRange\"" ">=1.0.0 <$TIMESTAMP.0.0"
    $YQ w -i "$MANIFEST_CSV_YAML" "metadata.annotations.containerImage" "${IMAGES[$OPERATOR_IMG]}"
    # pre-bundle
    $OPERATOR_SDK generate kustomize manifests -q
    $KUSTOMIZE build config/manifests | $OPERATOR_SDK generate bundle -q --overwrite --version "$RELEASE_VERSION" $BUNDLE_METADATA_OPTS
    $YQ d -i "$CSV_YAML" "spec.replaces"
    # operand images
    $YQ w -i "$CSV_YAML" "spec.install.spec.deployments[0].spec.template.spec.containers[0].image" "${IMAGES[$OPERATOR_IMG]}"
    $YQ w -i "$CSV_YAML" "spec.install.spec.deployments[0].spec.template.spec.containers[0].env[2].value" "${IMAGES[$IBM_BEDROCK_SHIM_IMG]}"
    # annotations
    $YQ w -i "$METADATA_YAML" "annotations.\"operators.operatorframework.io.bundle.package.v1\"" "$OPERATOR_NAME-app"
    $OPERATOR_SDK bundle validate ./bundle
}

# usage: prapare_operator_bundle <operand>:<tag>:<registry> ...;
function prepare_operator_bundle() {
    info "preparing map of image versions..."
    local DEFAULT_TAG="$RELEASE_VERSION"
    local DEFAULT_REG="scratch"

    for IMG in "${!IMG_NAMES[@]}"; do
        IMG_TAGS["$IMG"]="$DEFAULT_TAG"
        IMG_REGS["$IMG"]="${IMG_NAMES[$IMG]}"
    done

    while [[ "$#" -gt 0 ]]; do
        IMG=$(echo $1 | cut -f1 -d:)
        TAG=$(echo $1 | cut -f2 -d:)
        REG=$(echo $1 | cut -f3 -d:)
        IMG_TAGS["$IMG"]="$TAG"
        IMG_REGS["$IMG"]="$REG"
        shift
    done
    info "done"

    set_image_digests
    if [[ "$FORCE" != true ]]; then
        check_image_digests
    fi

    info "preparing operator bundle yamls..."
    prepare_operator_bundle_yamls
    info "done"
}

# usage: build_operator_bundle;
# prepare yamls and build bundle
function build_operator_bundle() {
    create_index_tags
    prepare_operator_bundle $OPERAND_VERSION_LIST
    build_multiarch "bundle.Dockerfile" "$OPERATOR_BUNDLE_IMG"
}

############################################################
#### Main functions
############################################################

COMMON_SERVICE_BASE_REGISTRY="hyc-cloud-private-daily-docker-local.artifactory.swg-devops.com/ibmcom"
COMMON_SERVICE_BASE_CATSRC="$COMMON_SERVICE_BASE_REGISTRY/ibm-common-service-catalog:latest-validated"
NEW_CUSTOM_CATSRC="crossplane-common-service-catalog"
PACKAGES="$OPERATOR_IMG-app"

DB_NAME="index.db"
PATH_TO_DB=./database

# usage: prepare_db;
# extract db file and change access mode to add new bundles
function prepare_db() {
    PATH_TO_DB=$(pwd)/database
    if [[ ! -d "$PATH_TO_DB" ]]; then
        mkdir "$PATH_TO_DB"
    fi
    rm -f "$PATH_TO_DB/$DB_NAME"
    local CONTAINER=$($CONTAINER_CLI run -d -v "$PATH_TO_DB":/opt/mount:z --rm "$COMMON_SERVICE_BASE_CATSRC")
    $CONTAINER_CLI exec "$CONTAINER" cp /database/index.db /opt/mount/"$DB_NAME"
    $CONTAINER_CLI exec "$CONTAINER" chmod 777 /opt/mount/"$DB_NAME"
    $CONTAINER_CLI stop "$CONTAINER"
    PATH_TO_DB=$(basename $PATH_TO_DB)
}

# usage: list_packages $BUNDLES
function list_packages() {
    local BUNDLE
    local PACKAGE
    for BUNDLE in $(echo $1 | tr , ' '); do
        PACKAGE=$(echo $1 | cut -f1 -d: | cut -f3 -d/ )
        PACKAGES="$PACKAGES,$PACKAGE-app"
    done
}

# usage: update_registry <path to db>;
# creates updated registry with specified versions of operators
# passed as arguments
function update_registry() {
    if [[ "$BUNDLES" ]]; then
        list_packages $BUNDLES
        BUNDLES="$OPERATOR_BUNDLE_IMG,$BUNDLES"
    else
        BUNDLES="$OPERATOR_BUNDLE_IMG"
    fi
    $OPM registry rm \
        --packages "$PACKAGES" \
        --database "$1"/"$DB_NAME"
    $OPM registry add \
        --container-tool "$CONTAINER_CLI" \
        --bundle-images "$BUNDLES" \
        --database "$1"/"$DB_NAME"
    if [[ "$?" != 0 ]]; then
        erro "error while updating registry"
    fi
}

# usage: create_index;
function create_index() {
    info "creating index..."
    prepare_db
    update_registry "$PATH_TO_DB"
    local DOCKERFILE=index.Dockerfile
    cat >"$DOCKERFILE" <<EOL
FROM $COMMON_SERVICE_BASE_CATSRC AS builder 
FROM registry.access.redhat.com/ubi8/ubi-minimal:latest
LABEL operators.operatorframework.io.index.database.v1=/database/index.db
COPY $PATH_TO_DB/$DB_NAME  /database/index.db
COPY --from=builder /registry-server /registry-server
COPY --from=builder /bin/grpc_health_probe /bin/grpc_health_probe
EXPOSE 50051
ENTRYPOINT ["/registry-server"]
CMD ["--database", "/database/index.db"]
EOL
    for IMG in "${!IMG_NAMES[@]}"; do
        echo "LABEL $IMG ${IMAGES[$IMG]}" >>"$DOCKERFILE"
    done
    build_multiarch "$DOCKERFILE" "${CATSRC_TAGS[@]}"
    info "done"
}

# usage: create_index_tags;
# creates list of tags for index image
function create_index_tags() {
    if [[ "$USER_TAG" != "" ]]; then
        CATSRC_TAGS=("$REGISTRY/$NEW_CUSTOM_CATSRC:$USER_TAG")
    elif [[ "$CROSSPLANE_BRANCH" == "master" ]]; then
        CATSRC_TAGS=(
            "$REGISTRY/$NEW_CUSTOM_CATSRC:$RELEASE_VERSION"
            "$REGISTRY/$NEW_CUSTOM_CATSRC:$RELEASE_VERSION-$TIMESTAMP"
            "$REGISTRY/$NEW_CUSTOM_CATSRC:latest"
        )
    elif [[ "$CROSSPLANE_BRANCH" == "release-"* ]]; then
        CATSRC_TAGS=(
            "$REGISTRY/$NEW_CUSTOM_CATSRC:$RELEASE_VERSION"
            "$REGISTRY/$NEW_CUSTOM_CATSRC:$RELEASE_VERSION-$TIMESTAMP"
        )
    else
        CATSRC_TAGS=(
            "$REGISTRY/$NEW_CUSTOM_CATSRC:$CROSSPLANE_BRANCH"
            "$REGISTRY/$NEW_CUSTOM_CATSRC:$CROSSPLANE_BRANCH-$TIMESTAMP"
        )
    fi
}

############################################################
#### Main
############################################################

# read options
while [[ "$#" -gt 0 ]]; do
    OPTION="$1"
    shift
    case $OPTION in
    -ot | --operand-tags)
        if [[ "$1" != "" && "$1" != -* ]]; then
            OPERAND_VERSION_LIST=$(echo $1 | tr , ' ')
        fi
        shift
        ;;
    -ac | --artifactory-creds)
        if [[ "$1" != "" && "$1" != -* ]]; then
            ARTIFACTORY_USER=$(echo $1 | cut -f1 -d:)
            ARTIFACTORY_TOKEN=$(echo $1 | cut -f2 -d:)
        fi
        shift
        ;;
    -r | --registry)
        if [[ "$1" != "" && "$1" != -* ]]; then
            REGISTRY="$1"
        fi
        shift
        ;;
    -t | --tag)
        if [[ "$1" != "" && "$1" != -* && "$1" != "default" ]]; then
            USER_TAG="$1"
            OPERATOR_BUNDLE_IMG="$SCRATCH_REG/$OPERATOR_BUNDLE:$USER_TAG"
        fi
        shift
        ;;
    -b | --bundles)
        if [[ "$1" != "" && "$1" != -* ]]; then
            BUNDLES="$1"
        fi
        shift
        ;;
    -f | --force)
        FORCE=true
        shift
        ;;
    -h | --help)
        print_usage
        exit 0
        ;;
    *)
        erro "unknown option $1"
        ;;
    esac
done

setup

# prepare bundles
info "preparing operator bundle..."
build_operator_bundle
info "done"

info "build catsrc image..."
create_index
info "done"

for TAG in "${CATSRC_TAGS[@]}"; do
    info "pushed tag: $TAG"
done

cleanup 0
