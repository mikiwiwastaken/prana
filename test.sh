#!/usr/bin/env bash
# Preview a GRUB theme in QEMU without touching the real bootloader.
# Works on Arch, Debian/Ubuntu, Fedora/RHEL, openSUSE and others.
#
# Usage: ./test.sh [THEME_SRC_DIR]
#
# Optional environment overrides:
#   THEME_NAME=prana                 name of the theme directory inside the ISO
#   QEMU_DISPLAY="gtk,zoom-to-fit=on"  e.g. "sdl" if gtk is not available
set -euo pipefail

THEME_NAME="${THEME_NAME:-prana}"
THEME_SRC="${1:-./$THEME_NAME}"
QEMU_DISPLAY="${QEMU_DISPLAY:-gtk,zoom-to-fit=on}"

die() { echo "Error: $*" >&2; exit 1; }

# grub-mkrescue (Arch, Debian, Ubuntu...) vs grub2-mkrescue (Fedora, RHEL, openSUSE)
MKRESCUE=""
for c in grub-mkrescue grub2-mkrescue; do
  if command -v "$c" >/dev/null 2>&1; then MKRESCUE="$c"; break; fi
done
[[ -n "$MKRESCUE" ]] || die "grub-mkrescue / grub2-mkrescue not found.
  Arch:          pacman -S grub libisoburn mtools
  Debian/Ubuntu: apt install grub-pc-bin grub-common xorriso mtools
  Fedora/RHEL:   dnf install grub2-tools-extra grub2-pc-modules xorriso mtools
  openSUSE:      zypper install grub2 xorriso mtools"

command -v xorriso >/dev/null 2>&1 || die "xorriso not found (needed by $MKRESCUE)"
command -v qemu-system-x86_64 >/dev/null 2>&1 || die "qemu-system-x86_64 not found (install qemu)"

[[ -d "$THEME_SRC" ]]           || die "theme source not found: $THEME_SRC"
[[ -f "$THEME_SRC/theme.txt" ]] || die "theme.txt not found in $THEME_SRC"
compgen -G "$THEME_SRC/*.pf2" >/dev/null || die "no .pf2 fonts in $THEME_SRC"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/iso/boot/grub/themes"
cp -r "$THEME_SRC" "$WORK/iso/boot/grub/themes/$THEME_NAME"

# Load every PF2 font in the theme, like 00_header does on a real system
FONTS=""
for f in "$WORK/iso/boot/grub/themes/$THEME_NAME"/*.pf2; do
  FONTS+="loadfont /boot/grub/themes/$THEME_NAME/$(basename "$f")"$'\n'
done

cat > "$WORK/iso/boot/grub/grub.cfg" <<EOF
set timeout=60
set timeout_style=menu
insmod all_video
insmod gfxterm
insmod gfxmenu
insmod png
insmod jpeg
set gfxmode=1920x1080
terminal_output gfxterm
${FONTS}
set theme=/boot/grub/themes/$THEME_NAME/theme.txt

menuentry "Arch Linux" --class arch --class gnu-linux { true }
menuentry "Arch Linux (fallback initramfs)" --class arch --class gnu-linux { true }
menuentry "Windows Boot Manager" --class windows --class os { true }
menuentry "UEFI Firmware Settings" { true }
EOF

LOG="$WORK/mkrescue.log"
"$MKRESCUE" -o "$WORK/test.iso" "$WORK/iso" >"$LOG" 2>&1 \
  || { cat "$LOG" >&2; die "$MKRESCUE failed"; }

qemu-system-x86_64 \
  -m 512 -cdrom "$WORK/test.iso" \
  -vga std -display "$QEMU_DISPLAY"
