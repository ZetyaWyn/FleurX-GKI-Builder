#!/bin/bash
# build.sh - GKI Kernel Builder (5.10 Only)
#
# Usage: ./build.sh <VARIANT> <CI|Release>
#   VARIANT = Vanilla | <ROOT> | <ROOT>_SUSFS
#   ROOT    = KSU | KSUN | BAKASU | SUKISU | FINASU

set -eo pipefail

die() {
    echo "Error: $*" >&2
    exit 1
}

if [ ! -f "config.sh" ]; then
    die "config.sh not found!"
fi
# shellcheck source=config.sh
source config.sh

# ==========================================
# Variant handling
# ==========================================
ROOT="none"      # none | KSU | KSUN | BAKASU | SUKISU | FINASU
SUSFS=0          # 1 = SUSFS enabled

parse_variant() {
    local v="$1" base="$1"
    SUSFS=0
    if [[ "$v" == *_SUSFS ]]; then
        SUSFS=1
        base="${v%_SUSFS}"
    fi
    case "$base" in
        Vanilla)
            [ "$SUSFS" -eq 0 ] || die "Variant '$v' is invalid: Vanilla has no root to attach SUSFS to."
            ROOT="none" ;;
        KSU|KSUN|BAKASU|SUKISU|FINASU)
            ROOT="$base" ;;
        *)
            die "Unknown variant '$v'. Use Vanilla, KSU, KSUN, BAKASU, SUKISU or FINASU, optionally with a _SUSFS suffix." ;;
    esac
}

# Fills ROOT_REPO / ROOT_BRANCH / ROOT_COMMIT / ROOT_DIR / ROOT_LABEL from config.sh
load_root_settings() {
    local key="$ROOT" repo_var branch_var commit_var
    [ "$ROOT" == "none" ] && return 0
    # KernelSU-Next + SUSFS uses the fork that already carries the SUSFS hooks
    if [ "$ROOT" == "KSUN" ] && [ "$SUSFS" -eq 1 ]; then
        key="KSUN_SUSFS"
    fi
    repo_var="ROOT_${key}_REPO"
    branch_var="ROOT_${key}_BRANCH"
    commit_var="ROOT_${key}_COMMIT"
    ROOT_REPO="${!repo_var:-}"
    ROOT_BRANCH="${!branch_var:-}"
    ROOT_COMMIT="${!commit_var:-}"
    [ -n "$ROOT_REPO" ] && [ -n "$ROOT_BRANCH" ] || die "Missing $repo_var / $branch_var in config.sh"
    case "$ROOT" in
        KSU)    ROOT_DIR="KernelSU";      ROOT_LABEL="KernelSU" ;;
        KSUN)   ROOT_DIR="KernelSU-Next"; ROOT_LABEL="KernelSU-Next" ;;
        BAKASU) ROOT_DIR="BakaSU";        ROOT_LABEL="BakaSU" ;;
        SUKISU) ROOT_DIR="SukiSU-Nova";   ROOT_LABEL="SukiSU-Nova" ;;
        FINASU) ROOT_DIR="FinaSU";        ROOT_LABEL="FinaSU" ;;
    esac
}

# ==========================================
# Telegram
# ==========================================
tg_send_msg() {
    if [ -n "${TG_BOT_TOKEN:-}" ] && [ -n "${TG_CHAT_ID:-}" ]; then
        curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
            -F chat_id="${TG_CHAT_ID}" \
            -F parse_mode="HTML" \
            -F text="$1" >/dev/null || true
    fi
}
tg_send_doc() {
    if [ -n "${TG_BOT_TOKEN:-}" ] && [ -n "${TG_CHAT_ID:-}" ]; then
        curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendDocument" \
            -F chat_id="${TG_CHAT_ID}" \
            -F document="@$1" \
            -F caption="$2" \
            -F parse_mode="HTML" >/dev/null || true
    fi
}

# Reports a failure to Telegram, then aborts. Needed because `set -e` would
# otherwise exit silently as soon as `make` or a patch step fails.
fail_build() {
    local what="$1"
    echo "-> Build Failed: $what"
    tg_send_msg "❌ <b>Build Failed!</b>
<b>Variant:</b> <code>${VARIANT:-?}</code>
<b>Step:</b> <code>${what}</code>"
    exit 1
}

# ==========================================
# Root implementation
# ==========================================
# Run from the kernel source root. Clones the selected root implementation and
# links it into drivers/kernelsu. Only one root is ever integrated.
setup_root() {
    local dir="$ROOT_DIR" actual drivers_dir="drivers" n

    # Drop any KernelSU already present in the source tree
    for p in drivers/staging/kernelsu drivers/kernelsu; do
        if [ -e "$p" ] || [ -L "$p" ]; then
            echo "Removing existing $p"
            local parent
            parent=$(dirname "$p")
            [ -f "$parent/Kconfig" ]  && sed -i '/kernelsu/d' "$parent/Kconfig"
            [ -f "$parent/Makefile" ] && sed -i '/kernelsu/d' "$parent/Makefile"
            rm -rf "$p"
        fi
    done
    rm -rf KernelSU KernelSU-Next BakaSU SukiSU-Ultra SukiSU-Nova FinaSU

    echo "-> Cloning ${ROOT_LABEL} (${ROOT_REPO}, ${ROOT_COMMIT:-$ROOT_BRANCH})..."
    # Full history (blobs on demand): the KSU version number counts commits.
    git clone --quiet --filter=blob:none --no-checkout "$ROOT_REPO" "$dir"
    if [ -n "$ROOT_COMMIT" ]; then
        [[ "$ROOT_COMMIT" =~ ^[0-9a-f]{40}$ ]] || die "Root commit for ${ROOT_LABEL} must be a full 40-character SHA."
        git -C "$dir" checkout --quiet --detach "$ROOT_COMMIT" 2>/dev/null || {
            git -C "$dir" fetch --quiet origin "$ROOT_COMMIT"
            git -C "$dir" checkout --quiet --detach "$ROOT_COMMIT"
        }
    else
        git -C "$dir" checkout --quiet -B "$ROOT_BRANCH" "origin/$ROOT_BRANCH"
    fi
    actual=$(git -C "$dir" rev-parse HEAD)
    if [ -n "$ROOT_COMMIT" ] && [ "$actual" != "$ROOT_COMMIT" ]; then
        die "Root commit mismatch: expected $ROOT_COMMIT, got $actual"
    fi
    ROOT_COMMIT_USED="$actual"

    [ -f "$dir/kernel/Kconfig" ] && [ -f "$dir/kernel/Makefile" ] \
        || die "${ROOT_LABEL} checkout has no kernel/Kconfig or kernel/Makefile; wrong repo or branch?"

    # A detached (pinned) checkout breaks the git-based KSU_VERSION heuristic in
    # Kbuild, so pin the number explicitly in that case.
    if [ -n "$ROOT_COMMIT" ] && [ -f "$dir/kernel/Kbuild" ] && grep -q 'BASE_BRANCH' "$dir/kernel/Kbuild"; then
        local count tag
        count=$(git -C "$dir" rev-list --count HEAD)
        tag=$(git -C "$dir" describe --tags --abbrev=0 2>/dev/null || echo unknown)
        {
            echo ''
            echo '# CI: fixed KSU_VERSION for a pinned commit'
            echo "KSU_VERSION := $((30000 + count))"
            echo "KSU_VERSION_TAG := \"$tag\""
        } >> "$dir/kernel/Kbuild"
    fi

    # Roots that do not carry SUSFS hooks need the SUSFS glue patch
    if [ "$SUSFS" -eq 1 ] && [ "$ROOT" == "KSU" ]; then
        local ksu_patch="$SUSFS_DIR/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"
        [ -f "$ksu_patch" ] || die "SUSFS repo has no $ksu_patch (needed for ${ROOT_LABEL})"
        echo "-> Applying SUSFS glue patch to ${ROOT_LABEL}..."
        (cd "$dir" && patch -p1 --no-backup-if-mismatch < "$ksu_patch") \
            || die "SUSFS glue patch does not apply to ${ROOT_LABEL} at ${actual:0:12}"
    fi

    ln -sfn "../$dir/kernel" "$drivers_dir/kernelsu"
    grep -q 'kernelsu/' "$drivers_dir/Makefile" \
        || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$drivers_dir/Makefile"
    if ! grep -q 'drivers/kernelsu/Kconfig' "$drivers_dir/Kconfig"; then
        n=$(grep -n '^endmenu' "$drivers_dir/Kconfig" | tail -1 | cut -d: -f1)
        [ -n "$n" ] || die "No endmenu found in $drivers_dir/Kconfig"
        sed -i "${n}i source \"drivers/kernelsu/Kconfig\"" "$drivers_dir/Kconfig"
    fi
}

# Appends the defconfig options for the selected root
root_configs() {
    local cfg="arch/arm64/configs/$KERNEL_DEFCONFIG"
    {
        echo "# Root: $ROOT_LABEL"
        echo "CONFIG_KSU=y"
        case "$ROOT" in
            BAKASU)
                echo "CONFIG_KSU_MULTI_MANAGER_SUPPORT=n"
                echo "CONFIG_KSU_TOOLKIT_SUPPORT=y" ;;
            FINASU)
                echo "CONFIG_KSU_DYNAMIC_MANAGER=n" ;;
        esac
        # These roots ship SUSFS Kconfig options built in; keep them off without SUSFS
        if [ "$SUSFS" -eq 0 ] && { [ "$ROOT" == "BAKASU" ] || [ "$ROOT" == "SUKISU" ] || [ "$ROOT" == "FINASU" ]; }; then
            for s in KSU_SUSFS KSU_SUSFS_SUS_PATH KSU_SUSFS_SUS_MOUNT KSU_SUSFS_SUS_KSTAT \
                     KSU_SUSFS_SPOOF_UNAME KSU_SUSFS_ENABLE_LOG KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS \
                     KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG KSU_SUSFS_OPEN_REDIRECT KSU_SUSFS_SUS_MAP; do
                echo "CONFIG_${s}=n"
            done
        fi
    } >> "$cfg"
}

# ==========================================
# SUSFS (kernel side)
# ==========================================
susfs_fetch() {
    SUSFS_DIR="$WORKDIR/susfs"
    if [ ! -d "$SUSFS_DIR" ]; then
        git clone --depth=1 -q https://gitlab.com/simonpunk/susfs4ksu -b "$SUSFS_BRANCH" "$SUSFS_DIR"
    fi
}

susfs_kernel_patch() {
    local patches="$SUSFS_DIR/kernel_patches"
    cp -R "$patches"/fs/* ./fs/
    cp -R "$patches"/include/* ./include/

    # No `|| true`: a failed or half-applied SUSFS patch must stop the build
    if ! patch -p1 --no-backup-if-mismatch < "$patches/50_add_susfs_in_${SUSFS_BRANCH}.patch"; then
        find . -name '*.rej' -print
        return 1
    fi
    if [ -n "$(find . -name '*.rej' -print -quit)" ]; then
        find . -name '*.rej' -print
        return 1
    fi

    cat << EOF >> arch/arm64/configs/$KERNEL_DEFCONFIG
# Extras
CONFIG_OVERLAY_FS_XINO_AUTO=y
CONFIG_KALLSYMS=y
CONFIG_TMPFS_POSIX_ACL=y
# SUSFS
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
EOF
}

# Checks the final .config really contains what this variant asked for.
# Kconfig silently drops options whose symbol does not exist.
verify_config() {
    local cfg="$OUTDIR/.config" missing=0 sym
    local want=()
    [ "$ENABLE_NTSYNC" == "true" ] && want+=("CONFIG_NTSYNC")
    [ "$ROOT" != "none" ] && want+=("CONFIG_KSU")
    [ "$SUSFS" -eq 1 ] && want+=("CONFIG_KSU_SUSFS")
    for sym in "${want[@]}"; do
        if ! grep -qE "^${sym}=[ym]$" "$cfg"; then
            echo "-> ${sym} is not enabled in the final .config"
            missing=1
        fi
    done
    return $missing
}

# ==========================================
# Release notes
# ==========================================
# Collected while building (one entry per variant)
RELEASE_ROOT_ROWS=()     # root table rows
SUSFS_COLS=()            # SUSFS table column headers
SUSFS_CELLS=()           # SUSFS table cells (same order as SUSFS_COLS)
NOMOUNT_COMMIT=""
SUSFS_COMMIT=""
SUSFS_VERSION_SEEN=""

# Writes the release page text to $1, in the same layout the Wild Kernels use:
# root table, feature list, SUSFS commits, then the assets listed by GitHub.
render_release_notes() {
    local out="$1" i
    {
        echo "# ${KERNEL_NAME} for GKI2 Devices"
        echo
        echo "**Kernel:** \`${LINUX_VERSION}\` (${KERNEL_BRANCH}) · **Compiler:** \`${COMPILER_STRING}\`"
        echo
        echo "> [!WARNING]"
        echo "> Back up your boot image before flashing, and report what breaks."
        echo

        if [ "${#RELEASE_ROOT_ROWS[@]}" -gt 0 ]; then
            echo "## Root"
            echo
            echo "| Root | Version | Commit |"
            echo "|------|---------|--------|"
            printf '%s\n' "${RELEASE_ROOT_ROWS[@]}"
            echo
        fi

        echo "## Features"
        echo
        [ -n "$SUSFS_VERSION_SEEN" ] && echo "- SUSFS ${SUSFS_VERSION_SEEN}"
        if [ -n "$NOMOUNT_COMMIT" ]; then
            echo "- NoMount [\`${NOMOUNT_COMMIT}\`](https://github.com/maxsteeel/nomount/commit/${NOMOUNT_COMMIT})"
        fi
        [ "$ENABLE_NTSYNC" == "true" ] && echo "- NTSync"
        for v in "${VARIANTS[@]}"; do
            [ "$v" == "Vanilla" ] && { echo "- Vanilla build (no root) included"; break; }
        done
        echo

        if [ "${#SUSFS_COLS[@]}" -gt 0 ]; then
            echo "## SUSFS commits"
            echo
            local head="| SUSFS branch |" sep="|--------------|" row="| ${SUSFS_BRANCH} |"
            for ((i = 0; i < ${#SUSFS_COLS[@]}; i++)); do
                head+=" ${SUSFS_COLS[$i]} |"
                sep+="---|"
                row+=" ${SUSFS_CELLS[$i]} |"
            done
            echo "$head"
            echo "$sep"
            echo "$row"
            echo
        fi

        echo "Flash the AnyKernel3 zip that matches your root manager from the assets below."
    } > "$out"
}

# ==========================================
# Main
# ==========================================
main() {
    INPUT_VARIANT=${1:-$DEFAULT_VARIANT}
    RELEASE_TYPE=${2:-$DEFAULT_RELEASE_TYPE}

    if [ "$RELEASE_TYPE" == "Release" ]; then
        VARIANTS=("${RELEASE_VARIANTS[@]}")
    else
        VARIANTS=("$INPUT_VARIANT")
    fi
    # Reject a bad variant before anything slow starts
    for v in "${VARIANTS[@]}"; do parse_variant "$v"; done

    WORKDIR="$(pwd)"
    OUTDIR="$WORKDIR/out"
    KSRC="$WORKDIR/ksrc"

    # Release needs gh and a token. Stop now, not after hours of compiling.
    if [ "$RELEASE_TYPE" == "Release" ]; then
        command -v gh &> /dev/null || die "Release build needs the gh CLI."
        [ -n "${GH_TOKEN:-}" ] || die "Release build needs the GH_TOKEN secret (upload to $RELEASE_REPO)."
        # Latest release tag (e.g. v1.0) -> bump the minor version
        LATEST_TAG=$(gh api repos/"$RELEASE_REPO"/releases/latest --jq '.tag_name' 2>/dev/null || true)
        if [ -z "$LATEST_TAG" ]; then
            RELEASE="v1.0"
        else
            MAJOR=$(echo "$LATEST_TAG" | grep -oP 'v\K\d+' || echo "1")
            MINOR=$(echo "$LATEST_TAG" | grep -oP '\.\K\d+' || echo "0")
            RELEASE="v${MAJOR}.$((MINOR + 1))"
        fi
    else
        # No versioning in CI, just use a date stamp
        RELEASE="CI-$(date +"%Y%m%d")"
    fi

    KERNEL_DEFCONFIG="gki_defconfig"
    SUSFS_BRANCH="gki-android12-5.10"

    sudo timedatectl set-timezone "$TIMEZONE" || export TZ="$TIMEZONE"

    echo "-> Downloading and setting up Clang..."
    CLANG_DIR="$WORKDIR/clang"
    if [ ! -d "$CLANG_DIR" ]; then
        wget -qO clang_archive "$CLANG_URL"
        mkdir -p "$CLANG_DIR"
        if [[ "$CLANG_URL" == *".tar.zst" ]]; then
            tar -I zstd -xf clang_archive -C "$CLANG_DIR"
        elif [[ "$CLANG_URL" == *".tgz" ]] || [[ "$CLANG_URL" == *".tar.gz" ]]; then
            tar -xf clang_archive -C "$CLANG_DIR"
        fi
        rm -f clang_archive
    fi
    export PATH="${CLANG_DIR}/bin:$PATH"
    COMPILER_STRING=$(clang --version | head -n 1 | sed 's/(https..*//' | sed 's/ version//')

    echo "-> Cloning Kernel Source..."
    if [ ! -d "$KSRC" ]; then
        git clone --depth=1 -b "$KERNEL_BRANCH" "$KERNEL_SOURCE" "$KSRC"
    fi

    cd "$KSRC"
    LINUX_VERSION=$(make kernelversion)
    k_lastcommit=$(git rev-parse --short HEAD)

    ZIP_FILES=()

    for VARIANT in "${VARIANTS[@]}"; do
        echo "-> Building Variant: $VARIANT"
        parse_variant "$VARIANT"
        ROOT_COMMIT_USED=""
        load_root_settings
        cd "$KSRC"

        # Reset kernel source to clean state (-ff also removes nested git clones)
        git checkout . -f
        git clean -ffd

        rm -rf "$OUTDIR"
        mkdir -p "$OUTDIR"

        # NoMount
        echo "-> Setting up NoMount..."
        curl -fsSL https://raw.githubusercontent.com/maxsteeel/nomount/refs/heads/dev/kernel/setup.sh | bash - \
            || fail_build "NoMount setup"
        NOMOUNT_COMMIT=$(git -C NoMount rev-parse --short=7 HEAD 2>/dev/null || echo "")

        # SUSFS (kernel side) comes before the root, because some roots need
        # the SUSFS repo for their own glue patch.
        if [ "$SUSFS" -eq 1 ]; then
            echo "-> Setting up SUSFS..."
            susfs_fetch || fail_build "SUSFS download"
            susfs_kernel_patch || fail_build "SUSFS kernel patch"
            SUSFS_COMMIT=$(git -C "$SUSFS_DIR" rev-parse --short=7 HEAD 2>/dev/null || echo "")
            SUSFS_VERSION=$(grep -E '^#define SUSFS_VERSION' ./include/linux/susfs.h | cut -d' ' -f3 | sed 's/"//g')
            SUSFS_VERSION_SEEN="$SUSFS_VERSION"
        else
            SUSFS_VERSION="None"
        fi

        # Root
        if [ "$ROOT" != "none" ]; then
            echo "-> Setting up ${ROOT_LABEL}..."
            setup_root
            root_configs
            ROOT_INFO="${ROOT_LABEL} @ ${ROOT_COMMIT_USED:0:9}"
            # Version shown by the manager = 30000 + number of commits
            ROOT_VERSION=$((30000 + $(git -C "$ROOT_DIR" rev-list --count HEAD)))
            ROOT_ROW_LABEL="$ROOT_LABEL"
            if [ "$ROOT" == "KSUN" ] && [ "$SUSFS" -eq 1 ]; then ROOT_ROW_LABEL="KernelSU-Next (SUSFS fork)"; fi
            ROOT_COMMIT_URL="${ROOT_REPO%.git}/commit/${ROOT_COMMIT_USED}"
            RELEASE_ROOT_ROWS+=("| ${ROOT_ROW_LABEL} | ${ROOT_VERSION} | [\`${ROOT_COMMIT_USED:0:7}\`](${ROOT_COMMIT_URL}) |")
            if [ "$SUSFS" -eq 1 ]; then
                SUSFS_COLS+=("${ROOT_ROW_LABEL}")
                SUSFS_CELLS+=("${SUSFS_VERSION} ( [\`${SUSFS_COMMIT}\`](https://gitlab.com/simonpunk/susfs4ksu/-/commit/${SUSFS_COMMIT}) )")
            fi
        else
            ROOT_INFO="None"
        fi

        # NoMount config
        echo "CONFIG_NOMOUNT=y" >> arch/arm64/configs/$KERNEL_DEFCONFIG

        # NTSync: the driver is already in this source tree, so only enable it
        if [ "$ENABLE_NTSYNC" == "true" ]; then
            [ -f drivers/misc/ntsync.c ] && grep -q '^config NTSYNC' drivers/misc/Kconfig \
                || fail_build "NTSync driver missing from kernel source"
            ./scripts/config --file arch/arm64/configs/$KERNEL_DEFCONFIG --enable NTSYNC
            NTSYNC_STATE="Enabled"
        else
            NTSYNC_STATE="Disabled"
        fi

        # Set Localversion
        ./scripts/config --file arch/arm64/configs/$KERNEL_DEFCONFIG --set-str CONFIG_LOCALVERSION "-$KERNEL_NAME/$RELEASE"
        ./scripts/config --file arch/arm64/configs/$KERNEL_DEFCONFIG --disable CONFIG_LOCALVERSION_AUTO
        sed -i 's/echo "+"/# echo "+"/g' scripts/setlocalversion

        # Build Variables
        export KBUILD_BUILD_USER="$KBUILD_USER"
        export KBUILD_BUILD_HOST="$KBUILD_HOST"
        KBUILD_BUILD_TIMESTAMP=$(date)
        export KBUILD_BUILD_TIMESTAMP
        export KCFLAGS="-w"

        MAKE_ARGS=(
          O="$OUTDIR"
          ARCH=arm64
          LLVM=1
          LLVM_IAS=1
          CROSS_COMPILE=aarch64-linux-gnu-
          CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
          CC=clang
        )

        echo "-> Building Kernel..."
        tg_send_msg "🚀 <b>Build Started</b>
<b>Kernel:</b> <code>${LINUX_VERSION}</code>
<b>Branch:</b> <code>${KERNEL_BRANCH}</code>
<b>Variant:</b> <code>${VARIANT}</code>
<b>Root:</b> <code>${ROOT_INFO}</code>
<b>NoMount:</b> <code>Enabled</code>
<b>NTSync:</b> <code>${NTSYNC_STATE}</code>
<b>Build Type:</b> <code>${RELEASE_TYPE}</code>"

        make "${MAKE_ARGS[@]}" $KERNEL_DEFCONFIG || fail_build "make defconfig"
        verify_config || fail_build "config check (option missing after defconfig)"
        make -j"$(nproc --all)" "${MAKE_ARGS[@]}" || fail_build "make"

        KERNEL_IMAGE="$OUTDIR/arch/arm64/boot/Image"
        [ -f "$KERNEL_IMAGE" ] || fail_build "no Image produced"

        tg_send_msg "✅ <b>Build Successful!</b>
<b>Variant:</b> <code>${VARIANT}</code>
<b>NoMount:</b> <code>Enabled</code>
<b>NTSync:</b> <code>${NTSYNC_STATE}</code>"

        # AnyKernel Packaging
        cd "$WORKDIR"
        if [ ! -d "AnyKernel3" ]; then
            git clone --depth=1 -b "$ANYKERNEL_BRANCH" "$ANYKERNEL_REPO" AnyKernel3
        fi

        # Same naming as your existing releases, e.g. Kitsune-SpiritFox-v1.18-5.10.272-KSUN_SUSFS.zip
        AK3_ZIP_NAME="${KERNEL_NAME}-${RELEASE}-${LINUX_VERSION}-${VARIANT}.zip"
        sed -i "s/kernel.string=.*/kernel.string=${KERNEL_NAME} ${RELEASE} ${LINUX_VERSION} ${VARIANT}/g" AnyKernel3/anykernel.sh
        sed -i "s/supported_kver=.*/supported_kver='5.10'/g" AnyKernel3/anykernel.sh

        rm -f AnyKernel3/Image AnyKernel3/Image.gz AnyKernel3/Image-dtb AnyKernel3/dtb AnyKernel3/*.zip
        cp "$KERNEL_IMAGE" AnyKernel3/

        (cd AnyKernel3 && zip -r9 "../${AK3_ZIP_NAME}" * -x .git README.md '*placeholder')
        ZIP_FILES+=("${AK3_ZIP_NAME}")

        # Set proper caption based on Build Type
        if [ "$RELEASE_TYPE" == "Release" ]; then
          HEADER="📦 <b>New Kernel Release!</b>"
        else
          HEADER="🧪 <b>New CI Build!</b>"
        fi

        MSG=$(cat << EOF
${HEADER}

<b>Version:</b> <code>${LINUX_VERSION}</code>
<b>Branch:</b> <code>${KERNEL_BRANCH}</code>
<b>Variant:</b> <code>${VARIANT}</code>
<b>Root:</b> <code>${ROOT_INFO}</code>
<b>NoMount:</b> <code>Enabled</code>
<b>NTSync:</b> <code>${NTSYNC_STATE}</code>
<b>SuSFS:</b> <code>${SUSFS_VERSION}</code>
<b>Compiler:</b> <code>${COMPILER_STRING}</code>
EOF
)
        if [ "$RELEASE_TYPE" != "Release" ]; then
            tg_send_doc "${AK3_ZIP_NAME}" "$MSG"
        fi
    done

    # Release (upload all variants to the same release)
    if [ "$RELEASE_TYPE" == "Release" ]; then
        echo "-> Creating GitHub Release..."
        NOTES_FILE="$WORKDIR/RELEASE_NOTES.md"
        render_release_notes "$NOTES_FILE"
        gh release create "${RELEASE}" "${ZIP_FILES[@]}" \
            --repo "$RELEASE_REPO" \
            --title "${KERNEL_NAME} ${RELEASE}" \
            --notes-file "$NOTES_FILE"

        # Send final announcement to Telegram with Link
        RELEASE_URL="https://github.com/${RELEASE_REPO}/releases/tag/${RELEASE}"
        RELEASE_MSG=$(cat << EOF
📦 <b>New Kernel Release!</b>

<b>Kernel:</b> <code>${LINUX_VERSION}</code>
<b>Branch:</b> <code>${KERNEL_BRANCH}</code>
<b>Variants:</b> <code>${VARIANTS[*]}</code>
<b>NoMount:</b> <code>Enabled</code>
<b>NTSync:</b> <code>${NTSYNC_STATE}</code>
<b>Tag:</b> <code>${RELEASE}</code>
<b>Compiler:</b> <code>${COMPILER_STRING}</code>

🔗 <a href="${RELEASE_URL}">GitHub Release Page</a>
EOF
)
        tg_send_msg "$RELEASE_MSG"
    fi

    echo "-> All tasks completed successfully!"
}

# Only run when executed, so the functions can be sourced for testing
if [ "${BASH_SOURCE[0]}" == "$0" ]; then
    main "$@"
fi
