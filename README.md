# Prana

A GRUB theme for Full HD (1920x1080) displays.

![Screenshot](screenshot.png)

## Requirements

- GRUB 2 as your bootloader
- A Full HD display
- Tested on: Arch Linux

The installer detects `grub-mkconfig` / `grub2-mkconfig` and `/boot/grub` / `/boot/grub2`,
so it should also work on Debian, Ubuntu, Fedora, RHEL-based distros and openSUSE.

## Installation

```bash
git clone https://github.com/mikiwiwastaken/prana
cd prana
sudo ./install.sh
```

The script copies the theme to `<grub dir>/themes/prana`, backs up
`/etc/default/grub`, updates the `GRUB_*` settings and regenerates `grub.cfg`.
It is safe to re-run.

If the theme files are not in `./prana`, pass the directory explicitly:

```bash
sudo ./install.sh /path/to/theme
```

## Testing in a VM (optional)

Preview the theme in QEMU without touching your bootloader. No root needed.

| Distro          | Packages                                                            |
| --------------- | ------------------------------------------------------------------- |
| Arch            | `qemu-desktop libisoburn mtools grub`                               |
| Debian / Ubuntu | `qemu-system-x86 xorriso mtools grub-pc-bin grub-common`            |
| Fedora / RHEL   | `qemu-system-x86 xorriso mtools grub2-tools-extra grub2-pc-modules` |
| openSUSE        | `qemu-x86 xorriso mtools grub2`                                     |

```bash
./test.sh
```

## Uninstall

```bash
sudo ./install.sh --uninstall
```
