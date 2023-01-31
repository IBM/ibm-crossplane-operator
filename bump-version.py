#
# Copyright 2022 IBM Corporation
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

import argparse
import re


BUNDLE_CSV_YAML = "./bundle/manifests/ibm-crossplane-operator.clusterserviceversion.yaml"
MANAGER_YAML = "./config/manager/manager.yaml"
CSV_YAML = "./config/manifests/bases/ibm-crossplane-operator.clusterserviceversion.yaml"
README = "./README.md"
RELEASE_VERSION_FILE = "./RELEASE_VERSION"
PREVIOUS_VERSION_FILE = "./PREVIOUS_VERSION"


def calculate_next_version(release_version : str, bump_type : str) -> str:
    splited_version = release_version.split('.')

    if bump_type == "patch":
        splited_version[2] = str(int(splited_version[2]) + 1)
    elif bump_type == "minor":
        splited_version[2] = "0"
        splited_version[1] = str(int(splited_version[1]) + 1)

    return '.'.join(splited_version)


def compare_versions(v1, v2):
    for e1, e2 in zip(v1, v2):
        if int(e1) > int(e2): 
            return 1
        if int(e1) < int(e2):
            return -1 
    return 0

def add_to_version_list_line(version_list : str, addition : str) -> str:

    versions = version_list[2:-1].split(', ')

    i = 0
    while i < len(versions):
        splitted_version = versions[i].split('.')
        splitted_addition = addition.split('.')
        if compare_versions(splitted_version, splitted_addition) == 1:
            break
        i += 1

    new_versions = [*versions[:i], addition, *versions[i:]]

    return f"{version_list[:2]}{', '.join(new_versions)}\n"




def get_release_version():
    try:
        with open("./RELEASE_VERSION") as f:
            return f.read().replace("\n", "")
    except OSError:
        print("Could not open RELEASE_VERSION file. Please ensure that you are in the root directory of the project when executing script")
        exit(1)

def get_previous_version():
    try:
        with open("./PREVIOUS_VERSION") as f:
            return f.read().replace("\n", "")
    except OSError:
        print("Could not open PREVIOUS_VERSION file. Please ensure that you are in the root directory of the project when executing script")
        exit(1)


def main():

    parser = argparse.ArgumentParser(description='Automatically update release version of IBM Crossplane operator.')
    parser.add_argument('-n', '--next-version',
                        help='next version number. Overrides bump_type')
    parser.add_argument('-b', '--bump-type', required=True, help="type of the upgrade (minor, patch)", choices=['minor', 'patch'])
    parser.add_argument('-s', '--shim-version', required=True, help="version of bedrock-shim image to be used")
    parser.add_argument("--verbose", help="increase output verbosity",
                    action="store_true")


    args = parser.parse_args()

    release_version = get_release_version()
    previous_version = get_previous_version()

    if args.next_version:
        next_version = args.next_version
    else:
        next_version = calculate_next_version(release_version, args.bump_type)

    print(f"Current version: {release_version}")
    print(f"Next version: {next_version}")

    files = [RELEASE_VERSION_FILE, CSV_YAML, BUNDLE_CSV_YAML, MANAGER_YAML, PREVIOUS_VERSION_FILE, README]

    for file in files:
        print(f"Changing version in {file}")
        with open(file, 'r') as f:
            lines = f.readlines()
        with open(file, 'w') as f:
            for line in lines:
                if re.fullmatch(r'- (\d+\.\d+\.\d+, )*\d+\.\d+\.\d+\n', line) != None:
                    changed = add_to_version_list_line(line, next_version)
                else:
                    # bump references to next version
                    changed=re.sub(rf'{release_version}', f'{next_version}', line)
                    # bump references to previous version
                    changed=re.sub(rf'{previous_version}', f'{release_version}', changed)
                    # bump references to bedrock-shim-config
                    changed=re.sub(rf'bedrock-shim-config:\d+\.\d+\.\d+', f'bedrock-shim-config:{args.shim_version}', changed)

                if args.verbose and line != changed:
                    print(f"-{line}+{changed}")
                f.write(changed)






if __name__ == "__main__":
    main()
