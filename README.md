# FreedomNAS Profiles

OS-specific translation files for FreedomNAS.

## Available Profiles

- **debian.json**: Debian, Ubuntu, Debian-based distributions
- **freebsd.json**: FreeBSD 13.0+
- **arch.json**: Arch Linux (community-maintained)

## Repository Structure

```
freedomnas-profiles/
├── debian.json             ← OS profile: commands for Debian/Ubuntu
├── freebsd.json            ← OS profile: commands for FreeBSD
├── arch.json                ← OS profile: commands for Arch Linux
├── init/                    ← Init-system profiles, separate from the OS
│   ├── systemd.json
│   ├── openrc.json
│   ├── runit.json
│   ├── s6.json
│   ├── dinit.json
│   └── bsd_rc.json
└── packages/                ← Optional packages, by category
    ├── MANIFEST.json         ← list of available categories
    ├── SCHEMA.md              ← full format spec
    ├── core.json              ← essential NAS packages (required)
    ├── samba-cifs.json
    ├── nfs.json
    ├── containers.json
    └── virtualization.json
```

## What Are Profiles?

Each OS profile (`debian.json`, `freebsd.json`, `arch.json`) is a JSON file that maps
abstract actions to native operating-system commands — user management, networking,
ZFS, Samba, NFS, boot chain, etc.

**Example (`zfs` category):**

```json
"zfs": {
  "pool_import": "zpool import -d /dev/disk/by-id {pool_name}",   // Debian
  "snapshot_create": "zfs snapshot {dataset}@{snap_name}"
}
```

On FreeBSD the same file would use the same action names, with different commands
where needed (e.g. `packages.install` is `apt install -y {package_name}` on Debian and
`pkg install -y {package_name}` on FreeBSD).

### Init-agnostic: `services` no longer lives in the OS profile

Service management (`start`, `stop`, `restart`, `enable`, ...) has been split out of
the OS profile and is now defined per init-system in `init/{init_system}.json`
(systemd, OpenRC, runit, s6, dinit, bsd_rc). The engine detects the running init
system (filesystem markers, falling back to the `init_system` field declared in the
OS profile) and merges the init profile into the OS profile at runtime — so the same
Debian install can run under systemd or, in the future, a different init system,
without touching `debian.json`.

### Optional packages: `packages/`

Non-essential packages (Samba, NFS, containers, virtualization) are no longer listed
directly in the OS profiles, but in separate files under `packages/`, one per
category, indexed in `packages/MANIFEST.json`. This lets the installer/WebUI offer
selectable optional features, and lets backups remember which categories were
installed for cross-distro disaster recovery. See `packages/README.md` and
`packages/SCHEMA.md` for the full details.

## How the Core Engine Uses Profiles

1. Detects the operating system (`debian` | `freebsd` | `arch`)
2. Loads the corresponding OS profile (`{os}.json`)
3. Detects the running init system and merges in `init/{init_system}.json`
4. Translates abstract actions into native commands
5. Executes commands safely (never `shell=True` unless required, never commands
   built by hand in Python code — see the "Golden Rule" in ARCHITECTURE.md)

```python
from freedomnas.engine import get_engine

engine = get_engine()

# On Debian: systemctl restart samba
# On FreeBSD: service samba restart
# On Arch: systemctl restart samba
engine.execute("services", "restart", service_name="samba")

# Get just the resolved command, without executing it
cmd = engine.get_command("bootloader", "build_uki",
                          dataset="rpool/ROOT/debian",
                          output_path="/boot/efi/EFI/Linux/debian-uki.efi",
                          kernel_version="6.1.0-amd64")
```

## Adding a New Distribution

See [CONTRIBUTING.md](CONTRIBUTING.md) for a complete guide.

## Structure of an OS Profile

```json
{
  "os_name": "Distribution Name",
  "os_family": "linux|bsd",
  "os_version": "version_spec",
  "init_system": "systemd",

  "users": { /* user management */ },
  "network": { /* network configuration */ },
  "packages": { /* package manager commands (apt/pkg/pacman) */ },
  "zfs": { /* ZFS commands */ },
  "samba": { /* Samba/SMB commands */ },
  "nfs": { /* NFS commands */ },
  "btrfs": { /* Btrfs commands — where supported */ },
  "bootloader": { /* build UKI (dracut) + register UEFI boot entry (efibootmgr) */ },
  "system": { /* system info/control */ }
}
```

`services` does **not** go here — it lives in `init/{init_system}.json` (see above).

### `bootloader`

FreedomNAS boots from a Unified Kernel Image (UKI) built with `dracut`, loaded
directly via `efibootmgr` on native UEFI. On legacy BIOS, the installer uses Clover
(vendored in `freedomnas-installer/assets/clover/`) to emulate UEFI — that part is
pure file I/O and requires no profile commands. The profile only exposes the two
OS-native commands:

```json
"bootloader": {
  "build_uki": "dracut --force --uefi --kernel-cmdline \"root=ZFS={dataset} rw\" {output_path} {kernel_version}",
  "efi_boot_entry": "efibootmgr --create --disk {disk} --part {part_num} --loader {loader_path} --label {label}"
}
```

Currently only present in `debian.json`; `freebsd.json` and `arch.json` still use
their existing boot configuration.

See the JSON files for complete examples of every category.
