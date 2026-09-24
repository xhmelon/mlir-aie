#!/usr/bin/env bash
##===- .cursor/install.sh - Cloud Agent bootstrap for IRON / MLIR-AIE -----===##
#
# Copyright (C) 2026 Advanced Micro Devices, Inc.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#
##===----------------------------------------------------------------------===##
#
# Idempotent setup for a Cursor Cloud Agent development environment. Builds the
# MLIR-AIE compiler toolchain from source (LLVM/MLIR pulled from a wheel) and
# installs the IRON Python runtime + Peano, matching the flow documented in
# README.md / docs/Building.md and exercised by the buildAndTestPythons CI job.
#
# The AMD Ryzen AI NPU itself is not present in the VM, so on-device execution
# (`make run`) is not available; the compiler, the hardware-independent lit test
# suites (e.g. `check-aie`), and full design compilation to xclbin/instruction
# streams all work.
#
# Safe to re-run: apt installs are no-ops when satisfied, submodules are
# reconciled in place, the venv is reused/upgraded, the 3.7 GB MLIR distro wheel
# is only downloaded once, and the C++ build is incremental (ninja).
#
##===----------------------------------------------------------------------===##

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export DEBIAN_FRONTEND=noninteractive

echo "==> [1/5] System packages"
# Build toolchain + Python dev headers + OpenSSL (bootgen) + libstdc++-14
# (clang, the default c++, links against the newest installed GCC's libstdc++).
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
  build-essential clang lld cmake ninja-build \
  python3.12 python3.12-venv python3.12-dev python3-pip \
  uuid-dev libssl-dev libstdc++-14-dev \
  git ca-certificates curl unzip \
  libopencv-dev python3-opencv

echo "==> [2/5] XRT userspace (xrt-smi, xclbinutil, aiebu-asm, pyxrt)"
# Userspace XRT only -- no amdxdna-dkms kernel driver (there is no NPU in the
# VM). Provides the binary tools aiecc needs to emit xclbin/PDI/ELF and the
# xrt-smi that utils/env_setup.sh probes for.
if ! command -v xrt-smi >/dev/null 2>&1; then
  sudo add-apt-repository -y ppa:amd-team/xrt
  sudo apt-get update -qq
  sudo apt-get install -y \
    libxrt2 libxrt-npu2 libxrt-dev libxrt-utils libxrt-utils-npu python3-xrt
fi

echo "==> [3/5] Git submodules (bootgen, aie-rt, aie_api, cmakeModules)"
git submodule update --init --recursive --force

echo "==> [4/5] Python venv + dev tooling + Peano (utils/env_install.sh --dev)"
export PYTHON=python3.12
# Sourced so the ironenv virtualenv stays active for the build below.
# --no-pre-commit: hooks are a contributor convenience, not needed to build/run.
source utils/env_install.sh --dev --no-pre-commit

echo "==> [5/5] Build MLIR-AIE from source (LLVM/MLIR from wheel)"
# Reuse the already-downloaded MLIR distro wheel when present to skip the
# ~3.7 GB re-download; ninja makes the actual compile incremental.
if [ -d my_install/mlir ]; then
  bash ./utils/build-mlir-aie-from-wheels.sh my_install/mlir
else
  bash ./utils/build-mlir-aie-from-wheels.sh
fi

echo ""
echo "==> Done. In a new shell, activate the toolchain with:"
echo "      source ironenv/bin/activate && source utils/env_setup.sh"
