# Repository Guidelines

## Project Structure & Module Organization
This repository is a Bash-driven Arch Linux setup toolkit. `install.sh` is the main entrypoint and orchestrates numbered modules in `scripts/` such as `01-preflight.sh`, `20-gnome.sh`, and `95-verify.sh`. Keep new installer phases in `scripts/` and preserve the numeric prefix ordering.

User-facing package selections live in `pkglists/`. Desktop and app configuration files belong in `dotfiles/common`, `dotfiles/gnome`, and `dotfiles/niri-dms`. Static assets such as wallpapers, Firefox defaults, and Windows fonts belong in `resources/`. Recovery helpers are kept at the repo root in `undochange.sh` and `de-undochange.sh`.

## Build, Test, and Development Commands
Use commands from a TTY on an Arch system:

- `sudo bash install.sh`: run the full installer locally.
- `BRANCH=main bash strap.sh`: bootstrap from a target branch and start installation.
- `sudo bash scripts/95-verify.sh`: run post-install verification for packages and deployed configs.
- `bash -n install.sh scripts/*.sh undochange.sh de-undochange.sh strap.sh`: syntax-check shell scripts before committing.
- `shellcheck install.sh scripts/*.sh`: optional local lint pass; useful even though no repo config is committed.

## Coding Style & Naming Conventions
Write Bash, not mixed-shell scripts. Follow the existing style: 4-space indentation, descriptive function names, uppercase exported globals (`BASE_DIR`, `STATE_FILE`), and lowercase local variables. Quote variable expansions, prefer small helpers in `scripts/00-utils.sh`, and keep comments short and operational.

Name new phase scripts as `NN-purpose.sh` so ordering stays obvious. Keep executable entry scripts at the repository root or inside `scripts/`.

## Testing Guidelines
There is no formal unit-test suite in this repository. Validation is script-focused: run `bash -n` for syntax, use `shellcheck` when available, and execute `scripts/95-verify.sh` after changes that affect package lists, dotfiles, or deployment flow. If you add a new module, include a safe re-run path and verify both success and missing-dependency cases.

## Commit & Pull Request Guidelines
Recent history shows short messages such as `fix` and `修改部分脚本`. Keep commits concise and imperative, but make them more specific when possible, for example: `niri: fix wallpaper path` or `installer: adjust flatpak step`.

Pull requests should include the affected install phase(s), the commands you ran, any required environment assumptions, and screenshots only for visible desktop/UI changes. Highlight risky areas such as partitioning, bootloader edits, rollback logic, or changes that require root.

## Security & Configuration Tips
Most scripts expect `root`; document any command that writes bootloader, Btrfs, Snapper, or user home state. Do not hardcode machine-specific secrets or personal paths outside the existing `/home/$TARGET_USER` patterns.
