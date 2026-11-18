#!/bin/bash
# config.sh - Configuration for GKI Kernel Builder

# ==========================================
# 1. Project Configuration
# ==========================================
KERNEL_NAME="Kitsune-SpiritFox"
KERNEL_SOURCE="https://github.com/ZetyaWyn/android_kernel_common-5.10"
KERNEL_BRANCH="android12-5.10"
KBUILD_USER="ZetyaWyn"
KBUILD_HOST="ZetyaWyn"
TIMEZONE="Asia/Kolkata"

# ==========================================
# 2. AnyKernel3 Configuration
# ==========================================
ANYKERNEL_REPO="https://github.com/zylhdrXP/AnyKernel3"
ANYKERNEL_BRANCH="gki"

# ==========================================
# 3. Toolchain Configuration
# ==========================================
CLANG_URL="https://github.com/Neutron-Toolchains/clang-build-catalogue/releases/download/06092026/neutron-clang-06092026.tar.zst"

# ==========================================
# 4. GitHub Release Configuration
# ==========================================
RELEASE_REPO="ZetyaWyn/Kitsune-SpiritFox-Release"

# ==========================================
# 5. Default Build Options
# ==========================================
# Variant = <ROOT> or <ROOT>_SUSFS. ROOT is one of:
#   Vanilla  (no root, never with _SUSFS)
#   KSU      tiann/KernelSU
#   KSUN     KernelSU-Next
#   BAKASU   BakaSU
#   SUKISU   SukiSU-Ultra
#   FINASU   FinaSU
#   KOWSU    KowSU
# Examples: Vanilla, KSUN, KSUN_SUSFS, BAKASU_SUSFS
DEFAULT_VARIANT="Vanilla"
# Options: CI, Release
DEFAULT_RELEASE_TYPE="CI"
# Variants built (and uploaded together) when the build type is Release
RELEASE_VARIANTS=("Vanilla" "KSUN_SUSFS")

# ==========================================
# 6. Kernel features
# ==========================================
# NTSync (/dev/ntsync, used by Wine/Proton). The driver already ships in this
# kernel source; the build only switches CONFIG_NTSYNC on and fails early if
# drivers/misc/ntsync.c is missing (a different source would need backports).
ENABLE_NTSYNC="true"

# ==========================================
# 7. Root implementations
# ==========================================
# REPO/BRANCH are cloned in full (history is needed for the KSU version number).
# COMMIT is optional: a full 40-character SHA pins the build; empty = branch tip.
ROOT_KSU_REPO="https://github.com/tiann/KernelSU"
ROOT_KSU_BRANCH="main"
ROOT_KSU_COMMIT=""

ROOT_KSUN_REPO="https://github.com/KernelSU-Next/KernelSU-Next"
ROOT_KSUN_BRANCH="dev"
ROOT_KSUN_COMMIT=""
# KSUN_SUSFS uses the fork that already carries the SUSFS hooks
ROOT_KSUN_SUSFS_REPO="https://github.com/pershoot/KernelSU-Next"
ROOT_KSUN_SUSFS_BRANCH="dev-susfs"
ROOT_KSUN_SUSFS_COMMIT=""

ROOT_BAKASU_REPO="https://github.com/Baka-SU/BakaSU"
ROOT_BAKASU_BRANCH="main"
ROOT_BAKASU_COMMIT=""

# 'builtin' is the branch meant to be compiled into the kernel
ROOT_SUKISU_REPO="https://github.com/SukiSU-Ultra/SukiSU-Ultra"
ROOT_SUKISU_BRANCH="builtin"
ROOT_SUKISU_COMMIT=""

ROOT_FINASU_REPO="https://github.com/LyraVoid/FinaSU"
ROOT_FINASU_BRANCH="master"
ROOT_FINASU_COMMIT=""

ROOT_KOWSU_REPO="https://github.com/KOWX712/KernelSU"
ROOT_KOWSU_BRANCH="master"
ROOT_KOWSU_COMMIT=""
