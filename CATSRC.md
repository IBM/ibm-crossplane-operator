# ibm-crossplane catalog source

Script `common/scripts/build_catsrc.sh` adds `ibm-crossplane-operator-app` package to `ibm-common-service-catalog`. Default images of operator and operands are:
* `ibm-crossplane-operator`: tag `1.0.1`, registry 'scratch'
* `ibm-crossplane`: tag `1.0.1`, registry 'scratch'

Script builds new image only if there is no catalog source image with selected tag or digests of selected operator/operand images were changed.

Resulting catalog source is pushed to `hyc-cloud-private-scratch-docker-local.artifactory.swg-devops.com/ibmcom/crossplane-common-service-catalog` (names of created images are shown at the end of script's output).
Tags depend on name of branch on which the script is being run:

* on master: tags latest, `<version>`, `<version>-<timestamp>` (eg. `1.0.1-12345`)
* on release-*: tags `<version>`, `<version>-<timestamp>`
* on `<name>`: tags `<name>`, `<name>-<timestamp>` (eg `pkopel-build-catsrc-12345`)

## Building
1. Export environment variables `ARTIFACTORY_USER` and `ARTIFACTORY_TOKEN` for pulling catalog source image from artifactory repository.
    ```
    export ARTIFACTORY_USER=<artifactory user name>
    export ARTIFACTORY_TOKEN=<artifactory token>
    ```
    Artifactory credentials can also be passed to the script via `-ac <artifactory user>:<artofactory token>` option.

2. (Optional) To change repository to which resulting image will be pushed export enviroment variable `REGISTRY` (default is `hyc-cloud-private-scratch-docker-local.artifactory.swg-devops.com/ibmcom/`).
    ```
    export REGISTRY=<docker repository>
    ```
    Repository address can also be passed to the script via `-r <docker repository>` option.

3. Run script `./common/scripts/build_catsrc.sh`. Options:
    * select operator and operand images using option `-ot <image name>:<tag>:<registry>`
    * specify catsrc image tag: `-t <tag>`
    * force build even if no changes detected: `-f `
    * pass artifactory credentials (overrides env variables): `-ac <artifactory user>:<artofactory token>`
    * specify docker repository for catsrc image: `-r <docker repository>`
    * show help: `-h`

## Installation
1. Export environment variables `ARTIFACTORY_USER` and `ARTIFACTORY_TOKEN` for pulling catalog source image from artifactory repository.
    ```
    export ARTIFACTORY_USER=<artifactory user name>
    export ARTIFACTORY_TOKEN=<artifactory token>
    ```

2. Log in to cluster with `oc` tool
    ```
    oc login -u <user name> -p <password/token> <cluster api address>
    ```

3. Update pull secrets and wait for each node to restart.
    ```
    ./common/scripts/update_global_pull_secrets.sh
    ```

3. Run instalation script
    ```
    ./common/scripts/update_catalogsource.sh <catsrc name> <catsrc image>
    ```
    ex. `./common/scripts/update_catalogsource.sh opencloud-operators hyc-cloud-private-scratch-docker-local.artifactory.swg-devops.com/ibmcom/crossplane-common-service-catalog:1.0.1`