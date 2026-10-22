# FreedomNAS Profiles

OS-specific translation files for FreedomNAS, split per module so that adding a new
module (core or community) never requires touching another module's profile.

## Available Profiles

- **os/os-debian.json**, **os/os-freebsd.json**, **os/os-arch.json**: shared OS-level
  primitives (package manager, bootloader, system info) for Debian/Ubuntu, FreeBSD 13.0+,
  and Arch Linux (community-maintained).
- **os/os-gentoo.json**, **os/os-artix.json**, **os/os-void.json**: Gentoo (Portage +
  OpenRC), Artix (pacman + OpenRC) and Void (xbps + runit) — community-maintained, and
  reachable at runtime: the engine maps `/etc/os-release`'s `ID` to a profile, and all
  three are in `SUPPORTED_OS`. Package categories carry matching sections; Gentoo's use
  full `category/name` atoms.
- **storage/**, **network/**, **shares/**, **users/**: per-module command fragments,
  one file per module per OS (`<module>-<os>.json`). A community module (e.g.
  `nextcloud`) ships its own `profiles/<name>/<name>-<os>.json` files the same way,
  usually inside its own repo/`.deb` rather than this one.

## Repository Structure

```
freedomnas-profiles/
├── os/                      ← Shared OS-level primitives (not owned by a module)
│   ├── os-debian.json         packages, bootloader, system, os_name/os_family/os_version
│   ├── os-freebsd.json
│   ├── os-arch.json
│   ├── os-gentoo.json         (community — portage + OpenRC)
│   ├── os-artix.json          (community — pacman + OpenRC)
│   └── os-void.json           (community — xbps + runit)
├── init/                    ← Init-system profiles, separate from the OS
│   ├── init-systemd.json
│   ├── init-openrc.json
│   ├── init-runit.json
│   ├── init-s6.json
│   ├── init-dinit.json
│   └── init-bsd_rc.json
├── storage/                 ← Storage module: zfs, media, zfs_properties
│   ├── storage-debian.json
│   ├── storage-freebsd.json
│   └── storage-arch.json / storage-gentoo.json / storage-artix.json / storage-void.json
├── network/                 ← Network module: network
│   └── network-<os>.json
├── shares/                  ← Shares module: samba, nfs
│   └── shares-<os>.json
├── users/                   ← Users module: users
│   └── users-<os>.json
├── installer/               ← Installer fragments: installer_meta, chroot,
│   ├── installer-debian.json    partitioning, rootpool, bootstrap, files.
│   ├── installer-gentoo.json    Consumed only by freedomnas-installer; the
│   ├── installer-void.json      engine merges them like any other fragment.
│   ├── installer-artix.json
│   ├── installer-arch.json
│   └── installer-freebsd.json
├── assets/                  ← Boot-chain and boot-time assets, shared by
│   ├── clover/                freedomnas-installer and freedomnas-image-builder
│   ├── zz-dracut-uki           (moved here from freedomnas-installer/assets/)
│   ├── firstboot.sh            ADR-002 boot-time decision point
│   ├── runitctl                runit service wrapper used by init-runit.json
│   └── supervisor.sh           WebUI supervisor (circuit breaker)
├── tests/runitctl/          ← runitctl + init-runit.json in Void, Artix, Debian
│                              and Devuan containers: `sh tests/runitctl/run.sh`
└── packages/                ← Optional packages, by category — NOT the same thing as
    ├── MANIFEST.json          the module profiles above. These describe distro package
    ├── SCHEMA.md              *groups* (samba-cifs, nfs, containers...) the installer/
    ├── core.json              WebUI can offer as install-time options and record for
    ├── samba-cifs.json        disaster recovery. `storage/`, `shares/`, etc. describe
    ├── nfs.json               the *commands* engine.py translates for a module at
    ├── containers.json        runtime. Same domain (storage, samba/nfs...), different
    └── virtualization.json    purpose — don't confuse the two.
```

## What Are Profiles?

Each per-OS fragment (`os/os-debian.json`, `storage/storage-debian.json`, ...) is a JSON
file that maps abstract actions to native operating-system commands — user management,
networking, ZFS, Samba, NFS, boot chain, etc. `engine.py` loads the `os/` fragment for
the detected OS as a base, then merges in the fragment from every other profile
subdirectory (`storage/`, `network/`, `shares/`, `users/`, and any community module's own
directory) that has a file matching `{directory}/{directory}-{os}.json`. Each fragment
contributes its own top-level category key(s) — there's no overlap to resolve.

**Example (`zfs` category, in `storage/storage-debian.json`):**

```json
"zfs": {
  "pool_import": "zpool import -d /dev/disk/by-id {pool_name}",   // Debian
  "snapshot_create": "zfs snapshot {dataset}@{snap_name}"
}
```

On FreeBSD the same category (in `storage/storage-freebsd.json`) uses the same action
names, with different commands where needed (e.g. `packages.install` in `os/os-debian.json`
is `apt install -y {package_name}`, vs. `pkg install -y {package_name}` in `os/os-freebsd.json`).

### Init-agnostic: `services` no longer lives in the OS profile

Service management (`start`, `stop`, `restart`, `enable`, ...) is defined per init-system
in `init/init-{init_system}.json` (systemd, OpenRC, runit, s6, dinit, bsd_rc). The engine
detects the running init system (filesystem markers, falling back to the `init_system`
field declared in the `os/` profile) and merges the init profile in at runtime — so the
same Debian install can run under systemd or, in the future, a different init system,
without touching `os/os-debian.json`.

### Optional packages: `packages/`

Non-essential packages (Samba, NFS, containers, virtualization) are listed in separate
files under `packages/`, one per category, indexed in `packages/MANIFEST.json`. This lets
the installer/WebUI offer selectable optional features, and lets backups remember which
categories were installed for cross-distro disaster recovery. See `packages/README.md`
and `packages/SCHEMA.md` for the full details. This is unrelated to the per-module
profile fragments above (see the note in the directory tree).

## How the Core Engine Uses Profiles

1. Detects the operating system (`debian` | `freebsd` | `arch`)
2. Loads the base `os/os-{os}.json` fragment
3. Scans every other profile subdirectory (`storage/`, `network/`, `shares/`, `users/`,
   plus any installed community module's directory) and merges in
   `{directory}/{directory}-{os}.json` when present
4. Detects the running init system and merges in `init/init-{init_system}.json`
5. Translates abstract actions into native commands
6. Executes commands safely (never `shell=True` unless required, never commands
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

## Adding a New Module

1. Pick a module id (e.g. `nextcloud`) and create `profiles/<id>/` (in this repo for a
   core module, or in the module's own repo for a community module).
2. Add `<id>-<os>.json` for each supported OS, containing only the category key(s) this
   module owns (don't duplicate categories already owned by `os/` or another module).
3. On the code side, add a matching `modules/<id>/manifest.json` declaring `supported_os`
   and the module's `entry_point` — see `freedomnas-core/modules/*/manifest.json` for the
   schema. The engine and the module loader pick up new fragments/modules automatically
   by directory scan; no existing file needs to change.

## Structure of an OS Profile Fragment

`os/os-<name>.json` (shared, not module-owned):

```json
{
  "os_name": "Distribution Name",
  "os_family": "linux|bsd",
  "os_version": "version_spec",
  "init_system": "systemd",

  "packages": { /* package manager commands (apt/pkg/pacman/xbps) */ },
  "bootloader": { /* build UKI (dracut) + register UEFI boot entry (efibootmgr) */ },
  "system": { /* system info/control */ }
}
```

Per-module fragments contain only the categories that module owns, e.g.
`storage/storage-<name>.json`:

```json
{
  "zfs": { /* ZFS commands, incl. encrypted pools + load-key for keymgmt.py */ },
  "media": { /* removable-device list/mount/unmount, for keymgmt.py's USB zero-touch unlock */ },
  "zfs_properties": { /* the properties this edition supports */ }
}
```

`services` does **not** go in any of these — it lives in `init/init-{init_system}.json`
(see above).

### `bootloader`

FreedomNAS boots from a Unified Kernel Image (UKI) built with `dracut`, loaded
directly via `efibootmgr` on native UEFI. On legacy BIOS, Clover (vendored in
this repo at `assets/clover/` — shared by `freedomnas-installer` and
`freedomnas-image-builder` so neither keeps its own copy) emulates UEFI —
that part is pure file I/O and requires no profile commands. The profile
only exposes the two OS-native commands:

```json
"bootloader": {
  "build_uki": "dracut --force --uefi --kernel-cmdline \"root=ZFS={dataset} rw\" {output_path} {kernel_version}",
  "efi_boot_entry": "efibootmgr --create --disk {disk} --part {part_num} --loader {loader_path} --label {label}"
}
```

`build_uki_recovery` builds the same UKI with `ro single` on the cmdline —
the read-only, single-user recovery entry the installer and the image builder
both place next to the normal one.

`os-freebsd.json` uses its own native boot chain instead (`install_gptzfsboot` /
`install_efi_loader`); `os-arch.json` has no `bootloader` section yet.

### `installer/installer-{edition}.json`

Everything `freedomnas-installer` needs to provision an edition, and the
reason no installation command lives in its Python:

| Section | Holds |
|---------|-------|
| `installer_meta` | Data, not commands: arch/suite/mirror(s), ESP size, bootstrap methods and the host tool each needs, UKI filenames, chroot directories |
| `chroot` | `exec_prefix` (prepended to every command run inside the target), plus the `mount`/`unmount` sequences |
| `partitioning` | Disk listing (fixed output contract), wipe, ESP + root partitions, ESP format/mount |
| `rootpool` | Root pool creation, the dataset tree, bootfs, mount/export, `.freedomnas` |
| `bootstrap` | The edition's own bootstrapper, the rootfs-tarball fetch/unpack, and the in-target cache/install/locale commands |
| `files` | The *contents* of OS-specific files: `sources.list`, `fstab`, `hosts`, `rc.conf`, `loader.conf`, the cron hook. A file's text is as distro-specific as a command |

Full schema in
[PROFILE_SPECIFICATION_v1.md](../freedomnas-specs/PROFILE_SPECIFICATION_v1.md#installer-profile-structure).

See the JSON files for complete examples of every category.
