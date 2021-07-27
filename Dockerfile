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
# Build the manager binary
FROM registry.access.redhat.com/ubi8/ubi-minimal:8.4-200.1622548483

ARG VCS_REF
ARG VCS_URL
ARG PLATFORM

LABEL org.label-schema.vendor="IBM" \
    org.label-schema.name="ibm-crossplane-operator" \
    org.label-schema.description="IBM Crossplane Operator" \
    org.label-schema.vcs-ref=$VCS_REF \
    org.label-schema.vcs-url=$VCS_URL \
    org.label-schema.license="Licensed Materials - Property of IBM" \
    org.label-schema.schema-version="1.0" \
    name="ibm-crossplane-operator" \
    vendor="IBM" \
    description="IBM Crossplane Operator" \
    summary="IBM Crossplane Operator" \
    release=$VCS_REF

ENV OPERATOR=/usr/local/bin/ibm-crossplane-operator/crossplane \
DEPLOY_DIR=/deploy \
USER_UID=1001 \
USER_NAME=ibm-crossplane-operator \
IMAGE_RELEASE="$IMAGE_RELEASE"

# binary generated from submodule ibm-crossplane
COPY ibm-crossplane/_output/bin/${PLATFORM}/crossplane ${OPERATOR}

COPY build /usr/local/bin
COPY bundle ${DEPLOY_DIR}
RUN /usr/local/bin/user_setup

# needed for crossplane binary
RUN mkdir /cache

# copy licenses
RUN mkdir /licenses
COPY LICENSE /licenses

ENTRYPOINT ["/usr/local/bin/entrypoint"]
USER ${USER_UID}
