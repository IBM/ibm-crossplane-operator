#! /usr/bin/env bash
############################################################
#### Helper functions
############################################################

SCRIPT_NAME=$(basename $0)
# text colours
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# usage: info <message>;
function info() {
    echo -e "${GREEN}[INFO]${NC} $SCRIPT_NAME: $1"
}

# usage: erro <message>;
function erro() {
    echo -e "${RED}[ERROR]${NC} $SCRIPT_NAME: $1"
    print_usage
    cleanup 1
}

# usage: print_usage;
function print_usage() {
    echo -e "Usage: $SCRIPT_NAME [-h] | [-t TAG] 

Build catalog source with ibm-crossplane-operator

Options:
 -t  | --tag TAG 
        Build ibm-crossplane-operator-bundle and ibm-common-service-catalog with TAG
 -h  | --help 
        Show this message
 -ac | --artifactory-creds USER:TOKEN
        Credentials for 'docker login' (by default sourced from 
        variables ARTIFACTORY_USER and ARTIFACTORY_TOKEN)
 -ot | --operand-tags OPERAND_TAG_LIST
        Build crossplane operator bundle with operand images with tags specified
        in OPERAND_TAG_LIST in format \"OPERAND_1:TAG_1:REG_1,...,OPERAND_N:TAG_N:REG_N\",
        default for every image are contents of file \"RELEASE_VERSION\"
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
        $CONTAINER_CLI login "$REGISTRY" -u "$ARTIFACTORY_USER" -p "$ARTIFACTORY_TOKEN"
        $CONTAINER_CLI login "$COMMON_SERVICE_BASE_REGISTRY" -u "$ARTIFACTORY_USER" -p "$ARTIFACTORY_TOKEN"
    fi
    RELEASE_VERSION=$(cat RELEASE_VERSION)
}

# usage: cleanup <exit code>;
function cleanup() {
    info "cleaning up"
    cd "$START_WD"
    rm -rf "$COMMON_SERVICE_TMP_DIR"
    exit $1
}

############################################################
#### Operator bundle functions
############################################################
#ibm-crossplane:1.0.0
#ibm-crossplane-bedrock-shim-config:1.0.0
#ibm-crossplane-operator:1.0.0
OPERATOR_IMG="ibm-crossplane-operator"
IBM_CROSSPLANE_IMG="ibm-crossplane"
#IBM_BEDROCK_SHIM_IMG="ibm-crossplane-bedrock-shim-config"
IMG_NAMES=($OPERATOR_IMG $IBM_CROSSPLANE_IMG $IBM_BEDROCK_SHIM_IMG)
declare -A IMG_TAGS
declare -A IMG_REGS
declare -A IMAGES

LICENSING_PACKAGE_NAME="ibm-licensing-operator-app"
BUNDLE_METADATA_OPTS="--channels=v3,beta --default-channel=v3"

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
        erro "could not find digest for $NAME:$TAG:$REG"
    else
        info "digest of $NAME:$TAG:$REG: $DIGEST"
        IMAGES["$NAME"]="$REGISTRY_URI/$NAME@$DIGEST"
    fi
}

# usage: set_image_digests;
function set_image_digests() {
    info "downloading image digests..."
    for IMG in "${IMG_NAMES[@]}"; do
        local TAG="${IMG_TAGS[$IMG]}"
        local REG="${IMG_REGS[$IMG]}"
        set_image_digest "$IMG" "$TAG" "$REG"
    done
    info "done"
}

# usage: check_image_digests;
function check_image_digests() {
    local OLD_CUSTOM_CATSRC=${TAGS[0]}
    local REG=$(echo $OLD_CUSTOM_CATSRC | cut -f1 -d.)
    local SUB_REG=$(echo $OLD_CUSTOM_CATSRC | cut -f2 -d/)
    local IMG=$(echo $OLD_CUSTOM_CATSRC | cut -f3 -d/ | cut -f1 -d:)
    local TAG=$(echo $OLD_CUSTOM_CATSRC | cut -f2 -d:)
    local URL="https://na.artifactory.swg-devops.com/artifactory/$REG/$SUB_REG/$IMG/$TAG"
    local RESP=$($CURL --user "$ARTIFACTORY_USER:$ARTIFACTORY_TOKEN" "$URL")
    if [[ $RESP == "" ]]; then
        local CHANGED=false
        info "pulling previous image with tag ${TAGS[0]}"
        $CONTAINER_CLI pull $OLD_CUSTOM_CATSRC
        info "looking for changes in images.."
        for IMG in "${IMG_NAMES[@]}"; do
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
    $KUSTOMIZE build config/manifests | $OPERATOR_SDK generate bundle -q --overwrite --version "$CSV_VERSION" "$BUNDLE_METADATA_OPTS"
    $YQ d -i "$CSV_YAML" "spec.replaces"
    # operand images
    $YQ w -i "$CSV_YAML" "spec.install.spec.deployments[0].spec.template.spec.containers[0].image = ${IMAGES[$OPERATOR_IMG]}"
    $OPERATOR_SDK bundle validate ./bundle
}

# usage: prapare_operator_bundle <operand>:<tag>:<registry> ...;
function prepare_operator_bundle() {
    info "preparing map of image versions..."
    local DEFAULT_TAG="$RELEASE_VERSION"
    local DEFAULT_REG="scratch"

    for IMG in "${IMG_NAMES[@]}"; do
        IMG_TAGS["$IMG"]="$DEFAULT_TAG"
        IMG_REGS["$IMG"]="$DEFAULT_REG"
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
    check_image_digests

    info "preparing operator bundle yamls..."
    prepare_operator_bundle_yamls
    info "done"
}

# usage: build_operator_bundle;
# prepare yamls and build bundle
function build_operator_bundle() {
    cd "$COMMON_SERVICE_TMP_DIR"
    CSV_VERSION=$(cat Makefile | grep "^CSV_VERSION ?=" | cut -f3 -d' ')
    create_index_tags
    prepare_operator_bundle $OPERAND_VERSION_LIST
    $CONTAINER_CLI build -f "bundle.Dockerfile" -t "$OPERATOR_BUNDLE_IMG" .
    #$CONTAINER_CLI push "$OPERATOR_BUNDLE_IMG"
    cd -
}

############################################################
#### Main functions
############################################################

declare -A VERSIONS
TIMESTAMP=$(date +%s)
REGISTRY="hyc-cloud-private-scratch-docker-local.artifactory.swg-devops.com/ibmcom"
COMMON_SERVICE_BASE_REGISTRY="hyc-cloud-private-daily-docker-local.artifactory.swg-devops.com/ibmcom"
COMMON_SERVICE_BASE_CATSRC="$COMMON_SERVICE_BASE_REGISTRY/ibm-common-service-catalog:cd"
NEW_CUSTOM_CATSRC="crossplane-common-service-catalog"
OPERATOR_BUNDLE="ibm-crossplane-operator-bundle"
OPERATOR_BUNDLE_IMG="$REGISTRY/$OPERATOR_BUNDLE:$TIMESTAMP"
BUNDLES="$OPERATOR_BUNDLE_IMG"
PACKAGES="ibm-crossplane-operator"

# usage: update_index;
# creates updated index
function update_index() {
    local LOCAL_CATSRC_IMG="$REGISTRY/$NEW_CUSTOM_CATSRC:$TIMESTAMP"
    local DOCKERFILE="index.Dockerfile"
    info "removing old packages..."
    $OPM index rm \
        --operators "$PACKAGES" \
        --from-index "$COMMON_SERVICE_BASE_CATSRC" \
        -t "$LOCAL_CATSRC_IMG"
    #$CONTAINER_CLI push "$LOCAL_CATSRC_IMG"
    info "adding new packages..."
    $OPM index add \
        --bundles "$BUNDLES" \
        --from-index "$LOCAL_CATSRC_IMG" \
        --generate
    if [[ "$?" != 0 ]]; then
        erro "error while updating index"
    fi
    for IMG in "${IMG_NAMES[@]}"; do
        echo "LABEL $IMG ${IMAGES[$IMG]}" >>"$DOCKERFILE"
    done
    $CONTAINER_CLI build -f "$DOCKERFILE" -t "$LOCAL_CATSRC_IMG" .
    for TAG in "${TAGS[@]}"; do
        $CONTAINER_CLI tag "$LOCAL_CATSRC_IMG" "$TAG"
        #$CONTAINER_CLI push "$TAG"
    done
}

# usage: create_index_tags;
# creates list of tags for index image
function create_index_tags() {
    if [[ "$USER_TAG" != "" ]]; then
        TAGS=("$REGISTRY/$NEW_CUSTOM_CATSRC:$USER_TAG")
    elif [[ "$LICENSING_BRANCH" == "master" ]]; then
        TAGS=(
            "$REGISTRY/$NEW_CUSTOM_CATSRC:$CSV_VERSION"
            "$REGISTRY/$NEW_CUSTOM_CATSRC:$CSV_VERSION-$TIMESTAMP"
            "$REGISTRY/$NEW_CUSTOM_CATSRC:latest"
        )
    elif [[ "$LICENSING_BRANCH" == "release-"* ]]; then
        TAGS=(
            "$REGISTRY/$NEW_CUSTOM_CATSRC:$CSV_VERSION"
            "$REGISTRY/$NEW_CUSTOM_CATSRC:$CSV_VERSION-$TIMESTAMP"
        )
    else
        TAGS=(
            "$REGISTRY/$NEW_CUSTOM_CATSRC:$LICENSING_BRANCH"
            "$REGISTRY/$NEW_CUSTOM_CATSRC:$LICENSING_BRANCH-$TIMESTAMP"
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
        if [[ "$1" != "" ]]; then
            OPERAND_VERSION_LIST=$(echo $1 | tr , ' ')
        fi
        shift
        ;;
    -ac | --artifactory-creds)
        if [[ "$1" != "" ]]; then
            ARTIFACTORY_USER=$(echo $1 | cut -f1 -d:)
            ARTIFACTORY_TOKEN=$(echo $1 | cut -f2 -d:)
        fi
        shift
        ;;
    -t | --tag)
        if [[ "$1" != "" && "$1" != "default" ]]; then
            USER_TAG="$1"
            OPERATOR_BUNDLE_IMG="$REGISTRY/$OPERATOR_BUNDLE:$USER_TAG"
            BUNDLES="$OPERATOR_BUNDLE_IMG"
        fi
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
update_index
info "done"

for TAG in "${TAGS[@]}"; do
    info "pushed tag: $TAG"
done

cleanup 0
