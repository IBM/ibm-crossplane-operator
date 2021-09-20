# IBM Crossplane Operator

> **Important:** Do not install this operator directly. Only install this operator using the IBM Common Services Operator. For more information about installing this operator and other Common Services operators, see [Installer documentation](http://ibm.biz/cpcs_opinstall). If you are using this operator as part of an IBM Cloud Pak, see the documentation for that IBM Cloud Pak to learn more about how to install and use the operator service. For more information about IBM Cloud Paks, see [IBM Cloud Paks that use Common Services](http://ibm.biz/cpcs_cloudpaks).

The IBM Crossplane Operator installs an IBM modified version of Crossplane, an open source Kubernetes add-on that extends any cluster with the ability to provision and manage cloud infrastructure, services, and applications using kubectl, GitOps, or any tool that works with the Kubernetes API.

For more information about the available IBM Cloud Platform Common Services, see the [IBM Knowledge Center](http://ibm.biz/cpcsdocs).

## Supported platforms

Red Hat OpenShift Container Platform 4.6 or newer installed on one of the following platforms:

- Linux x86_64
- Linux on Power (ppc64le)
- Linux on IBM Z and LinuxONE

## Operator versions

- 1.1.0

## Prerequisites

Before you install this operator, you need to first install the operator dependencies and prerequisites:

- For the list of operator dependencies, see the IBM Knowledge Center [Common Services dependencies documentation](http://ibm.biz/cpcs_opdependencies).

- For the list of prerequisites for installing the operator, see the IBM Knowledge Center [Preparing to install services documentation](http://ibm.biz/cpcs_opinstprereq).

## Documentation

To install the operator with the IBM Common Services Operator follow the the installation and configuration instructions within the IBM Knowledge Center.

- If you are using the operator as part of an IBM Cloud Pak, see the documentation for that IBM Cloud Pak. For a list of IBM Cloud Paks, see [IBM Cloud Paks that use Common Services](http://ibm.biz/cpcs_cloudpaks).
- If you are using the operator with an IBM Containerized Software, see the IBM Cloud Platform Common Services Knowledge Center [Installer documentation](http://ibm.biz/cpcs_opinstall).

## SecurityContextConstraints Requirements

The Platform API service requires running with the OpenShift Container Platform 4.x default restricted Security Context Constraints (SCCs).

To use a Custom SecurityContextConstraints definition:

1. Create and customize the following `ibm-crossplane-scc` SCC

Custom SecurityContextConstraints definition:
```
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  annotations:
    kubernetes.io/description: "This policy is the most restrictive for ibm-crossplane, 
      requiring pods to run with a non-root UID, and preventing pods from accessing the host.
      The UID and GID will be bound by ranges specified at the Namespace level." 
    cloudpak.ibm.com/version: "1.1.0"
  name: ibm-crossplane-scc
allowHostDirVolumePlugin: false
allowHostIPC: false
allowHostNetwork: false
allowHostPID: false
allowHostPorts: false
allowPrivilegeEscalation: true
allowPrivilegedContainer: false
allowedCapabilities: null
defaultAddCapabilities: null
fsGroup:
  type: MustRunAs
groups:
- system:authenticated
priority: null
requiredDropCapabilities:
- KILL
- MKNOD
- SETUID
- SETGID
runAsUser:
  type: MustRunAsRange
seLinuxContext:
  type: MustRunAs
supplementalGroups:
  type: RunAsAny
users: []
volumes:
- configMap
- downwardAPI
- emptyDir
- persistentVolumeClaim
- projected
- secret
```

2. Add the `ibm-crossplane-scc` SCC to `ibm-crossplane` service account
   
```
# oc adm policy add-scc-to-user ibm-crossplane-scc -z ibm-ibm-crossplane-operand
```

3. Restart the ibm-crossplane pods

```
# oc delete po -l app=ibm-crossplane
```

4. Verify the SCC is applied

```
# oc describe po -l app=ibm-crossplane | grep scc
```

For more information about the OpenShift Container Platform Security Context Constraints, see [Managing Security Context Constraints](https://docs.openshift.com/container-platform/4.6/authentication/managing-security-context-constraints.html).

## Backup and recovery

This operator does not persist any data. There is no backup and recovery procedure needed.

## Developer guide

If, as a developer, you are looking to build and test this operator to try out and learn more about the operator and its capabilities, you can use the following developer guide. This guide provides commands for a quick install and initial validation for running the operator.

> **Important:** The following developer guide is provided as-is and only for trial and education purposes. IBM and IBM Support does not provide any support for the usage of the operator with this developer guide. For the official supported install and usage guide for the operator, see the the IBM Knowledge Center documentation for your IBM Cloud Pak or for IBM Cloud Platform Common Services.

### Quick start guide

Use the following quick start commands for building and testing the operator:

#### Building and testing the operator using CLI

1. Build the bundle manifest to verify the CSV and the generated manifests

```
# make bundle
```

2. Build the operator

```
# make build-dev
```

3. Install the operator and deploy a sample CR

```
# make install
```

4. Verify the installation in `ibm-common-services` namespace

```
# oc -n ibm-common-services get po
NAME                                       READY   STATUS    RESTARTS   AGE
ibm-crossplane-7d6ff947df-pvg5t            1/1     Running   0          25s
ibm-crossplane-operator-6cc44f4c5c-p74lg   1/1     Running   0          73s
```

5. Verify the ibm-crossplane-bedrock-shim configuration package is installed

```
# oc get pkg
NAME                                                                 INSTALLED   HEALTHY   PACKAGE                                                         AGE
configuration.pkg.ibm.crossplane.io/ibm-crossplane-bedrock-shim-config   True        True      quay.io/opencloudio/ibm-crossplane-bedrock-shim-config:1.0.0   59s
```

#### Building and testing the operator using OLM

1. Build the bundle manifest to verify the CSV and the generated manifests

```
# make bundle
```

2. Build the operator

```
# make build
```

3. Build multi-arch images

```
# make images
```

4. Build the catalog source

```
# make build-catalog
```

5. Install the operator

```
# oc project ibm-common-services
# make install-operator
```

6. Verify the operator is running in `ibm-common-services` namespace

```
# oc -n ibm-common-services get po | grep crossplane
ibm-crossplane-operator-57bff8d56-98752                 1/1     Running   0          3m35s
```

7. Install the sample Crossplane CR

```
# make install-cr
```

8. Verify the Crossplane installation and configuration package.

```
# oc -n ibm-common-services get po | grep crossplane
ibm-crossplane-5d4bb64b5b-nx8w6                         1/1     Running   0          24s
ibm-crossplane-operator-57bff8d56-98752                 1/1     Running   0          6m18s
```

```
# oc get pkg
NAME                                                                 INSTALLED   HEALTHY   PACKAGE                                                         AGE
configuration.pkg.ibm.crossplane.io/ibm-crossplane-bedrock-shim-config   True        True      quay.io/opencloudio/ibm-crossplane-bedrock-shim-config:1.0.0   59s
```

### Debugging guide

Use the following commands to debug the operator:

#### Check the Cluster Service Version (CSV) installation status

```
# oc get csv
# oc describe csv ibm-crossplane-operator.<version>
```

#### Check the custom resource status

```
# oc describe crossplanes ibm-crossplane
# oc get crossplanes ibm-crossplane -o yaml
```

### Check the installed Crossplane configuration package

```
# oc get configurations
```

### Check the installed Crossplane Composite Resource Definitions (XRD)

```
# oc get xrd
```

### Check the installed Crossplane Compositions

```
# oc get compositions
```

### Check the Composite instances

For example, for Kafka
```
# oc get kafkacomposites
```

### Check the Claim instances

For example, for Kafka
```
# oc get kafkaclaims
```

#### Check the Crossplane operator status and log

```
# oc describe po -l name=ibm-crossplane-operator
# oc logs -f -l name=ibm-crossplane-operator
```

#### Check the Crossplane operand status and log

```
# oc describe po -l app=ibm-crossplane
# oc logs -f -l app=ibm-crossplane
```

### Multiple instances in a single cluster

If more than 1 replica is set and leader election is not enabled then controllers could conflict. Environment variable "LEADER_ELECTION" can be used to enable leader election process.'

### Operator namespace scoping
Operator support install modes:
 - OwnNamespace
 - SingleNamespace   
[more info](https://sdk.operatorframework.io/docs/building-operators/golang/operator-scope/)

### End-to-End testing

For more instructions on how to run end-to-end testing with the Operand Deployment Lifecycle Manager, see [ODLM guide](https://github.com/IBM/operand-deployment-lifecycle-manager/blob/master/docs/install/common-service-integration.md#end-to-end-test).
