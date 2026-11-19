# Automated GKI Kernel Builder

A robust, fully automated CI/CD pipeline for building Android GKI (Generic Kernel Image) kernels, powered by GitHub Actions. This builder supports automated patching for KernelSU-Next, SUSFS, and NoMount, AnyKernel3 packaging, Telegram notifications, and dynamic GitHub Release versioning.

## Features

*   **Automated Builds:** Trigger builds manually via GitHub Actions.
*   **Variant Support:** Choose `Vanilla` (no root) or one of six root implementations, with or without SUSFS: KernelSU (`KSU`), KernelSU-Next (`KSUN`), BakaSU (`BAKASU`), SukiSU-Ultra (`SUKISU`), FinaSU (`FINASU`) and KowSU (`KOWSU`). Add `_SUSFS` for SUSFS, e.g. `KSUN_SUSFS`.
*   **NTSync:** `CONFIG_NTSYNC` is enabled for every build (the driver is already in the kernel source). Set `ENABLE_NTSYNC="false"` in `config.sh` to turn it off.
*   **Auto-Versioning:** Automatically increments minor versions (e.g., v1.0 -> v1.1) for official releases, or uses date stamps for CI testing.
*   **Dynamic Configuration:** Easily switch kernel sources, toolchains, and release targets via a single configuration file without modifying the core build logic.
*   **Telegram Integration:** Sends build status and the final compiled zip directly to a Telegram chat.

## Configuration

All non-sensitive variables are located in `config.sh`. Before running your first build, verify the following parameters:

*   **Project Config:** `KERNEL_NAME`, `KERNEL_SOURCE`, `KERNEL_BRANCH`, `KBUILD_USER`, `KBUILD_HOST`
*   **Toolchain:** `CLANG_URL` (Direct link to the prebuilt clang tarball)
*   **Packaging:** `ANYKERNEL_REPO`, `ANYKERNEL_BRANCH`
*   **Releases:** `RELEASE_REPO` (The repository where official releases will be uploaded, e.g., `username/repo`) and `RELEASE_VARIANTS` (the variants built and uploaded together for a `Release`; default: one `Vanilla` zip plus one SUSFS zip for each of the six root managers)
*   **Roots:** `ROOT_<FLAVOR>_REPO`, `_BRANCH` and `_COMMIT`. Leave `_COMMIT` empty to follow the branch tip, or set a full 40-character SHA to pin the build.

### Variants

| Variant | Root | SUSFS hooks come from |
|---|---|---|
| `Vanilla` | none | n/a |
| `KSU` / `KSU_SUSFS` | tiann/KernelSU | SUSFS glue patch `10_enable_susfs_for_ksu` applied to KernelSU |
| `KSUN` | KernelSU-Next (`dev`) | n/a |
| `KSUN_SUSFS` | pershoot/KernelSU-Next (`dev-susfs`) | the fork itself |
| `BAKASU`, `SUKISU`, `FINASU` (+ `_SUSFS`) | BakaSU, SukiSU-Ultra (`builtin`), FinaSU | built into the root; SUSFS options are forced off in the non-SUSFS variant |
| `KOWSU` / `KOWSU_SUSFS` | KOWX712/KernelSU | SUSFS glue patch, same as KSU |

Only one root is ever added to the kernel. After `make gki_defconfig` the build checks that `CONFIG_NTSYNC`, `CONFIG_KSU` and `CONFIG_KSU_SUSFS` really ended up in `.config`, and stops with a Telegram message if one is missing.

## Secrets Setup

To enable Telegram notifications and GitHub Releases, you must configure the following secrets in your repository settings (**Settings > Secrets and variables > Actions**):

*   `TG_BOT_TOKEN`: Your Telegram Bot Token (obtained from @BotFather).
*   `TG_CHAT_ID`: The ID of the Telegram chat or channel where notifications should be sent.
*   `GH_TOKEN`: A Personal Access Token (PAT) required to upload files to the `RELEASE_REPO`.

### How to Generate a GitHub Token
If you are releasing to a different repository, the default GitHub Actions token will not have permission. You must generate a custom Personal Access Token:
1. Go to your GitHub Profile Settings -> **Developer settings** -> **Personal access tokens** -> **Tokens (classic)**.
2. Click **Generate new token (classic)**.
3. Give it a descriptive note (e.g., "GKI Builder Release").
4. Under **Scopes**, check the box for `repo` (Full control of private repositories).
5. Generate the token, copy it, and add it as a new repository secret named `GH_TOKEN` in your builder repository.

## How to Build

1. Navigate to the **Actions** tab in your GitHub repository.
2. Select the **Build GKI Kernel** workflow from the left sidebar.
3. Click the **Run workflow** dropdown on the right.
4. Select your desired parameters:
    *   **Kernel Variant:** `Vanilla` or `KSUN_SUSFS`
    *   **Build Type:** `CI` (Testing, no GitHub release) or `Release` (Auto-versioned and published to GitHub Releases)
5. Click **Run workflow**.

## Local Build (Optional)

If you prefer to run the script locally on a Linux machine with the necessary dependencies installed (`build-essential`, `clang`, etc.), simply execute:

```bash
chmod +x build.sh
./build.sh <VARIANT> <RELEASE_TYPE>
# Example: ./build.sh KSUN_SUSFS CI
```


### Release page

A `Release` build publishes one GitHub release with one AnyKernel3 zip per variant and generates the page text itself:

*   **Root**: each root's name, version (30000 + commit count, the number the manager shows) and a link to its commit.
*   **Features**: SUSFS version, NoMount commit, NTSync.
*   **SUSFS commits**: the SUSFS version and commit for each root, under the `gki-android12-5.10` branch.

Zips keep the existing naming, e.g. `Kitsune-SpiritFox-v1.18-5.10.272-KSUN_SUSFS.zip` and `...-Vanilla.zip`, so the release shows one zip per root manager.

To publish everything in one go: run the workflow with **release_type = Release**. The `variant` choice is ignored for a Release; it builds every entry in `RELEASE_VARIANTS` one after another and uploads them all to `RELEASE_REPO`. A failed variant stops the run before anything is published.
