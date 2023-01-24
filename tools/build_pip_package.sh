#!/bin/bash
# Copyright 2021 Google LLC.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.



# Create the TensorFlow Decision Forests pip package.
# This command uses the compiled artifacts generated by test_bazel.sh.
#
# Usage example:
#   # Generate the pip package with python3.8
#   ./tools/build_pip_package.sh python3.8
#
#   # Generate the pip package for all the versions of python using pyenv.
#   # Make sure the package are compatible with manylinux2014.
#   ./tools/build_pip_package.sh ALL_VERSIONS
#
#   # Generate the pip package for Apple ARM64 machines
#   ./tools/build_pip_package.sh ALL_VERSIONS_MAC_ARM64
#
#   # Generate the pip package for Apple Intel machines from Apple CPU machines
#   ./tools/build_pip_package.sh ALL_VERSIONS_MAC_INTEL_CROSSCOMPILE
#
# Requirements:
#
#   pyenv (if using ALL_VERSIONS_ALREADY_ASSEMBLED or ALL_VERSIONS)
#     See https://github.com/pyenv/pyenv-installer
#     Will be installed by this script if INSTALL_PYENV is set to INSTALL_PYENV.
#
#   Auditwheel
#     Auditwheel is required for Linux builds.
#     Auditwheel needs to be version 5.2.0. The script will attempt to
#     update Auditwheel to this version.
#

set -xve

PLATFORM="$(uname -s | tr 'A-Z' 'a-z')"
function is_macos() {
  [[ "${PLATFORM}" == "darwin" ]]
}

# Temporary directory used to assemble the package.
SRCPK="$(pwd)/tmp_package"

function check_auditwheel() {
  PYTHON="$1"
  shift
  local auditwheel_version="$(${PYTHON} -m pip show auditwheel | grep "Version:")"
  if [ "$auditwheel_version" != "Version: 5.2.0" ]; then
   echo "Auditwheel needs to be Version 5.2.0, currently ${auditwheel_version}"
   exit 1
  fi
}

# Pypi package version compatible with a given version of python.
# Example: Python3.8.2 => Package version: "38"
function python_to_package_version() {
  PYTHON="$1"
  shift
  ${PYTHON} -c 'import sys; print(f"{sys.version_info.major}{sys.version_info.minor}")'
}

# Installs dependency requirement for build the Pip package.
function install_dependencies() {
  PYTHON="$1"
  shift
  ${PYTHON} -m ensurepip -U || true
  ${PYTHON} -m pip install pip -U
  ${PYTHON} -m pip install setuptools -U
  ${PYTHON} -m pip install build -U
  ${PYTHON} -m pip install virtualenv -U
  ${PYTHON} -m pip install auditwheel==5.2.0
}

function check_is_build() {
  # Check the correct location of the current directory.
  if [ ! -d "bazel-bin" ]; then
    echo "This script should be run from the root directory of TensorFlow Decision Forests (i.e. the directory containing the LICENSE file) of a compiled Bazel export (i.e. containing a bazel-bin directory)"
    exit 1
  fi
}

# Collects the library files into ${SRCPK}
function assemble_files() {
  check_is_build

  rm -fr ${SRCPK}
  mkdir -p ${SRCPK}
  cp -R tensorflow_decision_forests LICENSE configure/setup.py configure/MANIFEST.in README.md ${SRCPK}

  # When cross-compiling, adapt the platform string.
  if [ ${ARG} == "ALL_VERSIONS_MAC_INTEL_CROSSCOMPILE" ]; then
    sed -i'.bak' -e "s/# plat = \"macosx_10_14_x86_64\"/plat = \"macosx_10_14_x86_64\"/" ${SRCPK}/setup.py
  fi

  # TFDF's wrappers and .so.
  SRCBIN="bazel-bin/tensorflow_decision_forests"
  cp ${SRCBIN}/tensorflow/ops/inference/inference.so ${SRCPK}/tensorflow_decision_forests/tensorflow/ops/inference/
  cp ${SRCBIN}/tensorflow/ops/training/training.so ${SRCPK}/tensorflow_decision_forests/tensorflow/ops/training/

  cp ${SRCBIN}/keras/wrappers.py ${SRCPK}/tensorflow_decision_forests/keras/

  # Distribution server binaries
  cp ${SRCBIN}/keras/grpc_worker_main ${SRCPK}/tensorflow_decision_forests/keras/

  # YDF's proto wrappers.
  YDFSRCBIN="bazel-bin/external/ydf/yggdrasil_decision_forests"
  mkdir -p ${SRCPK}/yggdrasil_decision_forests
  pushd ${YDFSRCBIN}
  find . -name \*.py -exec rsync -R -arv {} ${SRCPK}/yggdrasil_decision_forests \;
  popd

  # Add __init__.py to all exported Yggdrasil sub-directories.
  find ${SRCPK}/yggdrasil_decision_forests -type d -exec touch {}/__init__.py \;
}

# Build a pip package.
function build_package() {
  PYTHON="$1"
  shift

  pushd ${SRCPK}
  $PYTHON -m build
  popd

  cp -R ${SRCPK}/dist .
}

# Tests a pip package.
function test_package() {
  if [ ${ARG} == "ALL_VERSIONS_MAC_INTEL_CROSSCOMPILE" ]; then
    echo "Cross-compiled packages cannot be tested on the machine they're built with."
    return
  fi
  PYTHON="$1"
  shift
  PACKAGE="$1"
  shift

  PIP="${PYTHON} -m pip"

  if is_macos; then
    PACKAGEPATH="dist/tensorflow_decision_forests-*-cp${PACKAGE}-cp${PACKAGE}*-*.whl"
  else
    PACKAGEPATH="dist/tensorflow_decision_forests-*-cp${PACKAGE}-cp${PACKAGE}*.manylinux2014_x86_64.whl"
  fi
  ${PIP} install ${PACKAGEPATH}


  ${PIP} list
  ${PIP} show tensorflow_decision_forests -f

  # Run a small example
  ${PYTHON} examples/minimal.py

  rm -rf previous_package
  mkdir previous_package
  ${PYTHON} -m pip download --no-deps -d previous_package tensorflow-decision-forests
  local old_file_size=`du -k "previous_package" | cut -f1`
  local new_file_size=`du -k $PACKAGEPATH | cut -f1`
  local scaled_old_file_size=$(($old_file_size * 12))
  local scaled_new_file_size=$(($new_file_size * 10))
  if [ "$scaled_new_file_size" -gt "$scaled_old_file_size" ]; then
    echo "New package is 20% larger than the previous one."
    echo "This probably indicates a problem, aborting."
    exit 1
  fi
  scaled_old_file_size=$(($old_file_size * 8))
  if [ "$scaled_new_file_size" -lt "$scaled_old_file_size" ]; then
    echo "New package is 20% smaller than the previous one."
    echo "This probably indicates a problem, aborting."
    exit 1
  fi
}

# Builds and tests a pip package in a given version of python
function e2e_native() {
  PYTHON="$1"
  shift
  PACKAGE=$(python_to_package_version ${PYTHON})

  install_dependencies ${PYTHON}
  build_package ${PYTHON}

  # Fix package.
  if is_macos; then
    PACKAGEPATH="dist/tensorflow_decision_forests-*-cp${PACKAGE}-cp${PACKAGE}*-*.whl"
  else
    check_auditwheel ${PYTHON}
    PACKAGEPATH="dist/tensorflow_decision_forests-*-cp${PACKAGE}-cp${PACKAGE}*-linux_x86_64.whl"
    TF_DYNAMIC_FILENAME="libtensorflow_framework.so.2"
    ${PYTHON} -m auditwheel repair --plat manylinux2014_x86_64 -w dist --exclude ${TF_DYNAMIC_FILENAME} ${PACKAGEPATH}
  fi

  test_package ${PYTHON} ${PACKAGE}
}

# Builds and tests a pip package in Pyenv.
function e2e_pyenv() {
  VERSION="$1"
  shift

  # Don't force updating pyenv, we use a fixed version.
  # pyenv update

  ENVNAME=env_${VERSION}
  pyenv install ${VERSION} -s

  # Enable pyenv virtual environment.
  set +e
  pyenv virtualenv ${VERSION} ${ENVNAME}
  set -e
  pyenv activate ${ENVNAME}

  e2e_native python3

  # Disable virtual environment.
  pyenv deactivate
}

ARG="$1"
INSTALL_PYENV="$2"
shift | true

if [ ${INSTALL_PYENV} == "INSTALL_PYENV" ]; then 
  if ! [ -x "$(command -v pyenv)" ]; then
    echo "Pyenv not found."
    echo "Installing build deps, pyenv 2.3.5 and pyenv virtualenv 1.1.5"
    # Install python dependencies.
    sudo apt-get update
    sudo apt-get install -qq make build-essential libssl-dev zlib1g-dev \
              libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm \
              libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev \
              libffi-dev liblzma-dev patchelf
    git clone https://github.com/pyenv/pyenv.git
    (
      cd pyenv && git checkout bb0f2ae1a7867a06c1692e00efd3abe2113b8f83
    )
    PYENV_ROOT="$(pwd)/pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init --path)"
    eval "$(pyenv init -)"
    git clone --branch v1.1.5 https://github.com/pyenv/pyenv-virtualenv.git $(pyenv root)/plugins/pyenv-virtualenv
    eval "$(pyenv init --path)"
    eval "$(pyenv init -)"
    eval "$(pyenv virtualenv-init -)"
  fi
fi

if [ -z "${ARG}" ]; then
  echo "The first argument should be one of:"
  echo "  ALL_VERSIONS: Build all pip packages using pyenv."
  echo "  ALL_VERSIONS_ALREADY_ASSEMBLED: Build all pip packages from already assembled files using pyenv."
  echo "  Python binary (e.g. python3.8): Build a pip package for a specific python version without pyenv."
  exit 1
elif [ ${ARG} == "ALL_VERSIONS" ]; then
  # Compile with all the version of python using pyenv.
  assemble_files
  eval "$(pyenv init -)"
  e2e_pyenv 3.7.13
  e2e_pyenv 3.9.12
  e2e_pyenv 3.8.13
  e2e_pyenv 3.10.4
elif [ ${ARG} == "ALL_VERSIONS_ALREADY_ASSEMBLED" ]; then
  eval "$(pyenv init -)"
  e2e_pyenv 3.7.13
  e2e_pyenv 3.9.12
  e2e_pyenv 3.8.13
  e2e_pyenv 3.10.4
elif [ ${ARG} == "ALL_VERSIONS_MAC_ARM64" ]; then
  eval "$(pyenv init -)"
  assemble_files
  # Python 3.7 not supported for Mac ARM64
  e2e_pyenv 3.9.12
  e2e_pyenv 3.8.13
  e2e_pyenv 3.10.4
elif [ ${ARG} == "ALL_VERSIONS_MAC_INTEL_CROSSCOMPILE" ]; then
  eval "$(pyenv init -)"
  assemble_files
  # Python 3.7 not supported for Mac ARM64
  e2e_pyenv 3.9.12
  e2e_pyenv 3.8.13
  e2e_pyenv 3.10.4
else
  # Compile with a specific version of python provided in the call arguments.
  assemble_files
  PYTHON=${ARG}
  e2e_native ${PYTHON}
fi
