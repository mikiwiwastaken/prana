#!/usr/bin/env bash
# Install (or remove) a standalone GRUB theme and manage the related GRUB_* settings.
# Works on Arch, Debian/Ubuntu, Fedora/RHEL (and clones), openSUSE and most
# other distros that use GRUB2 with /etc/default/grub.
#
# Usage:
#   sudo ./install.sh [THEME_SRC_DIR]     install the theme
#   sudo ./install.sh --uninstall         restore /etc/default/grub and remove the theme
#   ./install.sh --help
#
# Optional environment overrides (rarely needed):
#   GRUB_DIR=/boot/grub2        directory that holds grub.cfg and themes/
#   GRUB_CFG=/path/to/grub.cfg  file that grub-mkconfig should write
#   GRUB_MKCONFIG=grub2-mkconfig
#   GFXMODE="1920x1080,auto"
#
# Safe to re-run: the theme dir is replaced and GRUB_* keys are updated in place.
set -euo pipefail

# ---- settings (edit here) ----------------------------------------------------
THEME_NAME="prana"
DEFAULT_FILE="/etc/default/grub"
GFXMODE="${GFXMODE:-1920x1080,auto}"
# -----------------------------------------------------------------------------

die()  { echo "Error: $*" >&2; exit 1; }
warn() { echo "Warning: $*" >&2; }

usage() {
  cat <<EOF
Usage:
  sudo $0 [THEME_SRC_DIR]    install the theme (default source: ./$THEME_NAME next to this script)
  sudo $0 --uninstall        restore the original $DEFAULT_FILE and remove the theme
  $0 --help                  show this help
EOF
}

# ---- 0. parse arguments ------------------------------------------------------
MODE="install"
THEME_SRC_ARG=""
for arg in "$@"; do
  case "$arg" in
    --uninstall|-u) MODE="uninstall" ;;
    --help|-h)      usage; exit 0 ;;
    -*)             usage >&2; die "unknown option: $arg" ;;
    *)              THEME_SRC_ARG="$arg" ;;
  esac
done
THEME_SRC="${THEME_SRC_ARG:-$(dirname "$(readlink -f "$0")")/$THEME_NAME}"

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "run with sudo"

# ---- 1. detect the distro's GRUB layout --------------------------------------
# NixOS / some immutable systems manage GRUB declaratively.
if [[ -e /etc/NIXOS ]] || { [[ -r /etc/os-release ]] && grep -qiE '^ID=nixos' /etc/os-release; }; then
  die "NixOS detected: set boot.loader.grub.theme in your configuration instead"
fi

# grub-mkconfig (Arch, Debian, Ubuntu, Gentoo, Void...) vs grub2-mkconfig (Fedora, RHEL, openSUSE)
if [[ -z "${GRUB_MKCONFIG:-}" ]]; then
  for c in grub-mkconfig grub2-mkconfig; do
    if command -v "$c" >/dev/null 2>&1; then GRUB_MKCONFIG="$c"; break; fi
  done
fi
[[ -n "${GRUB_MKCONFIG:-}" ]] || die "grub-mkconfig / grub2-mkconfig not found (is GRUB installed?)"

# /boot/grub (most distros) vs /boot/grub2 (Fedora, RHEL, openSUSE)
if [[ -z "${GRUB_DIR:-}" ]]; then
  for d in /boot/grub /boot/grub2; do
    if [[ -d "$d" ]]; then GRUB_DIR="$d"; break; fi
  done
fi
[[ -n "${GRUB_DIR:-}" && -d "$GRUB_DIR" ]] || die "no GRUB directory found in /boot (set GRUB_DIR=...)"

# Target grub.cfg. Older RHEL-family UEFI installs keep the real config on the ESP;
# a tiny file there is just a stub that points at $GRUB_DIR/grub.cfg.
if [[ -z "${GRUB_CFG:-}" ]]; then
  GRUB_CFG="$GRUB_DIR/grub.cfg"
  for efi_cfg in /boot/efi/EFI/*/grub.cfg; do
    [[ -f "$efi_cfg" ]] || continue
    if [[ $(wc -c <"$efi_cfg") -gt 2048 ]]; then GRUB_CFG="$efi_cfg"; break; fi
  done
fi

THEME_ROOT="$GRUB_DIR/themes"
THEME_DIR="$THEME_ROOT/$THEME_NAME"
THEME_TXT="$THEME_DIR/theme.txt"

echo "==> Using: $GRUB_MKCONFIG -> $GRUB_CFG (themes in $THEME_ROOT)"

[[ -f "$DEFAULT_FILE" ]] || die "$DEFAULT_FILE not found"

# Regenerate grub.cfg and print the tool's output.
regenerate() {
  echo "==> Regenerating $GRUB_CFG"
  local out
  out="$("$GRUB_MKCONFIG" -o "$GRUB_CFG" 2>&1)" || { echo "$out" >&2; die "$GRUB_MKCONFIG failed"; }
  echo "$out"
}

# ==============================================================================
# UNINSTALL
# ==============================================================================
if [[ "$MODE" == "uninstall" ]]; then
  # Backups are named <file>.<theme>.<timestamp>.bak, so the glob sorts oldest first.
  # The oldest one is the state from before the theme was first installed.
  backups=("$DEFAULT_FILE.$THEME_NAME".*.bak)

  # Keep the current file, in case it was edited after installing the theme.
  # The name does not match the glob above, so it is never picked as a restore source.
  PRE="$DEFAULT_FILE.$THEME_NAME-uninstall.$(date +%Y%m%d-%H%M%S).bak"
  cp -a "$DEFAULT_FILE" "$PRE"
  echo "==> Backup of current file: $PRE"

  if [[ -f "${backups[0]}" ]]; then
    echo "==> Restoring ${backups[0]}"
    cp -a "${backups[0]}" "$DEFAULT_FILE"
  else
    warn "no backup of $DEFAULT_FILE found; only disabling GRUB_THEME"
    sed -i -E 's|^[[:space:]]*(GRUB_THEME=)|# \1|' "$DEFAULT_FILE"
  fi

  # Regenerate first, delete the theme afterwards: if grub-mkconfig fails,
  # the files that grub.cfg still refers to are still there.
  regenerate

  if [[ -d "$THEME_DIR" ]]; then
    echo "==> Removing $THEME_DIR"
    rm -rf "$THEME_DIR"
  fi

  if grep -q "themes/$THEME_NAME/theme.txt" "$GRUB_CFG"; then
    warn "$GRUB_CFG still references the theme; check $DEFAULT_FILE and /etc/default/grub.d/"
    exit 1
  fi
  echo "==> OK: theme removed (backups kept as $DEFAULT_FILE.$THEME_NAME*.bak)"
  exit 0
fi

# ==============================================================================
# INSTALL
# ==============================================================================
[[ -d "$THEME_SRC" ]]            || die "theme source not found: $THEME_SRC"
[[ -f "$THEME_SRC/theme.txt" ]]  || die "theme.txt not found in $THEME_SRC"

# Every file the theme references should exist before anything is replaced.
for f in background.png select_w.png select_c.png select_e.png; do
  [[ -f "$THEME_SRC/$f" ]] || die "missing $f in $THEME_SRC"
done
compgen -G "$THEME_SRC/*.pf2" >/dev/null || die "no .pf2 fonts in $THEME_SRC"

# ---- 1. copy theme -----------------------------------------------------------
echo "==> Copying theme to $THEME_DIR"
mkdir -p "$THEME_ROOT"
rm -rf "$THEME_DIR"
cp -r "$THEME_SRC" "$THEME_DIR"
chmod -R a+rX "$THEME_DIR"
# Fix SELinux labels on Fedora/RHEL if the tool exists (harmless elsewhere).
if command -v restorecon >/dev/null 2>&1; then restorecon -R "$THEME_DIR" 2>/dev/null || true; fi

# ---- 2. update /etc/default/grub ---------------------------------------------
BACKUP="$DEFAULT_FILE.$THEME_NAME.$(date +%Y%m%d-%H%M%S).bak"
cp -a "$DEFAULT_FILE" "$BACKUP"
echo "==> Backup: $BACKUP"

# Replace an active KEY=... line (all of them), or append if there is none.
# Commented-out lines are left alone.
set_key() {
  local key="$1" value="$2"
  if grep -qE "^[[:space:]]*${key}=" "$DEFAULT_FILE"; then
    sed -i -E "s|^[[:space:]]*${key}=.*|${key}=\"${value}\"|" "$DEFAULT_FILE"
  else
    printf '%s="%s"\n' "$key" "$value" >> "$DEFAULT_FILE"
  fi
}

set_key GRUB_THEME           "$THEME_TXT"
set_key GRUB_GFXMODE         "$GFXMODE"
set_key GRUB_TERMINAL_OUTPUT "gfxterm"
set_key GRUB_TIMEOUT_STYLE   "menu"

# A wallpaper set via GRUB_BACKGROUND would override the theme background.
sed -i -E 's|^[[:space:]]*(GRUB_BACKGROUND=)|# \1|' "$DEFAULT_FILE"

echo "==> Current theme-related settings:"
grep -nE '^(GRUB_THEME|GRUB_GFXMODE|GRUB_TERMINAL_OUTPUT|GRUB_TIMEOUT_STYLE)=' "$DEFAULT_FILE"

# Debian/Ubuntu (and some others) also read /etc/default/grub.d/*.cfg, which can
# silently override what we just wrote.
if compgen -G "/etc/default/grub.d/*.cfg" >/dev/null; then
  if grep -lE '^[[:space:]]*(GRUB_THEME|GRUB_GFXMODE|GRUB_TERMINAL_OUTPUT|GRUB_TIMEOUT_STYLE|GRUB_BACKGROUND)=' \
       /etc/default/grub.d/*.cfg 2>/dev/null; then
    warn "the files listed above in /etc/default/grub.d/ set theme-related keys and may override them"
  fi
fi

# ---- 3. regenerate grub.cfg --------------------------------------------------
# Re-read the value GRUB will really use (including grub.d overrides), and make
# sure the file exists.
# shellcheck disable=SC1090
(
  set +eu
  source "$DEFAULT_FILE"
  for g in /etc/default/grub.d/*.cfg; do [[ -f "$g" ]] && source "$g"; done
  [[ -f "${GRUB_THEME:-}" ]]
) || die "GRUB_THEME does not point to an existing file"

regenerate

# Check the generated config instead of relying on a distro-specific log line.
if grep -q "themes/$THEME_NAME/theme.txt" "$GRUB_CFG"; then
  echo "==> OK: theme is referenced in $GRUB_CFG"
else
  warn "theme path not found in $GRUB_CFG; check GRUB_THEME and the theme files."
  exit 1
fi
