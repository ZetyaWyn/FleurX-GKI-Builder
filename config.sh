#!/bin/bash
# config.sh - Configuration for GKI Kernel Builder

# ==========================================
# 1. Project Configuration
# ==========================================
KERNEL_NAME="Kitsune-SpiritFox"
KERNEL_SOURCE="https://github.com/ZetyaWyn/android_kernel_common-5.10"
KERNEL_BRANCH="android12-5.10"
KBUILD_USER="zerotwo"
KBUILD_HOST="ZeroTwo"
TIMEZONE="Asia/Kolkata"

# ==========================================
# 2. AnyKernel3 Configuration
# ==========================================
ANYKERNEL_REPO="https://github.com/zylhdrXP/AnyKernel3"
ANYKERNEL_BRANCH="gki"

# ==========================================
# 3. Toolchain Configuration
# ==========================================
CLANG_URL="https://github.com/Neutron-Toolchains/clang-build-catalogue/releases/download/30072026/neutron-clang-30072026.tar.zst"

# ==========================================
# 4. GitHub Release Configuration
# ==========================================
RELEASE_REPO="zerotwo-alt/Kitsune-SpiritFox-Release"

# ==========================================
# 5. Default Build Options
# ==========================================
# Options: Vanilla, ReSukiSU_SUSFS
DEFAULT_VARIANT="Vanilla"
# Options: CI, Release
DEFAULT_RELEASE_TYPE="CI"
