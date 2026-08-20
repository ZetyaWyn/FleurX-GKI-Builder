#!/bin/bash
# config.sh - Configuration for GKI Kernel Builder

# ==========================================
# 1. Project Configuration
# ==========================================
KERNEL_NAME="Kitsune-SpiritFox"
KERNEL_SOURCE="https://github.com/project-sm7435/android_kernel_xiaomi_sm7435"
KERNEL_BRANCH="Staging"
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
RELEASE_REPO="https://github.com/ZetyaWyn/Kitsune-SpiritFox-Release-OSS"

# ==========================================
# 5. Default Build Options
# ==========================================
# Options: Vanilla, KSUN_SUSFS
DEFAULT_VARIANT="Vanilla"
# Options: CI, Release
DEFAULT_RELEASE_TYPE="CI"
