# FreedomNAS Package Management System

## Overview

The FreedomNAS package management system is a **modular, category-based architecture** that enables:

✓ **Multi-distribution support** — Debian, FreeBSD, Arch (and extensible to others; Artix and Void already have category entries and are listed in `supported_editions`, though the core engine doesn't select them at runtime yet)  
✓ **Edition switching** — Migrate between distros during setup  
✓ **Disaster recovery** — Restore full functionality across different OS versions  
✓ **Flexible deployments** — Choose optional features during installation  
✓ **Community contributions** — Easy to add new distributions or categories  

## Quick Start

### For Users Installing FreedomNAS

During installation, you'll be asked to select optional features:

```
FreedomNAS 4.0 Setup
===================

[✓] Core NAS (required)
    Essential ZFS, SSH, networking

[ ] Samba/CIFS (optional)
    Windows file sharing

[ ] NFS (optional)
    Unix/Linux file sharing

[ ] Containers (optional)
    Docker/Podman for applications

[ ] Virtualization (optional)
    KVM/Bhyve for VMs

Selected: 3 packages, 42 dependencies
Install: [Yes] [No]
```

All selected categories will be saved to `packages.yaml`. If disaster strikes, your backup will remember these choices.

### For Developers: Adding a New Category

1. Create a JSON file in this directory:

```json
{
  "category": "my-feature",
  "description": "My feature description",
  "debian": {
    "packages": ["pkg1", "pkg2"],
    "services": ["svc1"],
    "config_paths": ["/etc/my-feature.conf"]
  },
  "freebsd": { ... },
  "arch": { ... }
}
```

2. Add to `MANIFEST.json`:

```json
{
  "id": "my-feature",
  "name": "My Feature",
  "description": "...",
  "required": false,
  "file": "my-feature.json"
}
```

3. Push to Codeberg — the system will auto-detect it!

### For Distribution Maintainers: Adding Support for a New OS

To add Debian-based distros (Ubuntu, Linux Mint) or other variants:

1. Edit each category JSON file
2. Add the new OS entry alongside existing ones:

```json
{
  "debian": { ... },
  "ubuntu": {        // New!
    "packages": ["zfsutils-linux", ...],
    "services": [...],
    "config_paths": [...]
  },
  "freebsd": { ... },
  "arch": { ... }
}
```

3. Update `MANIFEST.json` to list the new edition
4. Test and submit a PR

## Architecture

### Directory Structure

```
packages/
├── MANIFEST.json          ← All categories and their metadata
├── SCHEMA.md              ← Full specification and format
├── README.md              ← This file
├── core.json              ← Essential NAS packages (required)
├── samba-cifs.json        ← Samba/SMB file sharing (optional)
├── nfs.json               ← NFS file sharing (optional)
├── containers.json        ← Docker/Podman containers (optional)
└── virtualization.json    ← KVM/Bhyve hypervisor (optional)
```

### System Files (After Installation)

```
/etc/freedomnas/packages.yaml          ← Installed categories and versions
/var/backups/freedomnas/               ← Backup storage
  ├── core-2026-05-22_14-30-00.tar.gz
  ├── samba-cifs-2026-05-22_14-45-00.tar.gz
  └── freedomnas-backup-2026-05-22/    ← Full system backup
      ├── packages.yaml
      ├── core-*.tar.gz
      ├── samba-cifs-*.tar.gz
      └── containers-*.tar.gz
```

## How It Works

### Installation Flow

1. **Display Options** — WebUI/Installer reads `MANIFEST.json` and shows categories
2. **User Selects** — User checks boxes for desired features
3. **Install Packages** — For each category, installer:
   - Reads category JSON
   - Looks up OS-specific packages
   - Calls OS package manager (apt, pkg, pacman)
   - Enables services
4. **Save State** — Installer writes `packages.yaml` with:
   - Which categories are installed
   - Installation date/version
   - Backup locations

### Disaster Recovery Flow

**Scenario:** Your FreedomNAS failed. You boot from a fresh Debian installation.

1. **Restore Backup** — Run: `sudo freedomnas restore /path/to/backup.tar.gz`
2. **Detect Setup** — System reads `packages.yaml` from backup:
   - Edition: Debian
   - Installed: core, samba-cifs, containers
3. **Install Packages** — For current OS (Debian), install:
   - core packages (zfsutils, ssh, etc.)
   - samba-cifs packages (samba, winbind, etc.)
   - containers packages (docker, docker-compose, etc.)
4. **Restore Configs** — Extract backed-up files:
   - `/etc/samba/smb.conf` ← from samba-cifs backup
   - `/etc/docker/daemon.json` ← from containers backup
5. **Start Services** — Enable and start all services
6. **Verify** — Check that all services are running

**Even Better:** If you want to **switch to FreeBSD**, the same backup works! The system:
- Reads Debian's packages.yaml
- Looks up FreeBSD equivalents in the category JSONs
- Installs FreeBSD versions of samba, docker, etc.
- Restores configs (paths may differ, handled automatically)
- You're back online on FreeBSD!

## Python API

### Using PackageManager

```python
from freedomnas_core.package_manager import PackageManager

pm = PackageManager()

# List all categories
for cat in pm.get_categories():
    print(f"{cat['id']}: {cat['name']} ({'required' if cat.get('required') else 'optional'})")

# Get packages for a specific OS
debian_core = pm.get_packages_for_os("core", "debian")
print(debian_core)
# → ['zfsutils-linux', 'openssh-server', ...]

# Get services to enable
services = pm.get_services_for_os("samba-cifs", "freebsd")
print(services)
# → ['samba']

# Get config paths for backup
configs = pm.get_config_paths("containers", "arch")
print(configs)
# → ['/etc/docker/daemon.json']
```

### Recording what is installed

The categories a system has are kept in `config.yaml` under
`installed_features`, written by the installer and read by the reconciler.
There is no separate `packages.yaml`: the module that maintained one was
removed once it became clear nothing ever called it, and that the appliance
restores itself by re-applying the desired state rather than by putting saved
files back.


## Design Principles

### 1. **No Hardcoded Package Names**
Package names are defined in JSON files, not buried in installer code. Changes to distro package names don't require code updates.

### 2. **Edition-Agnostic**
The installer is written once, works on all supported OSes. OS differences are encapsulated in JSON.

### 3. **Easy Community Contributions**
Adding a new OS or feature doesn't require code changes—just JSON files.

### 4. **Portable Backups**
A backup from Debian includes metadata (`packages.yaml`) describing what was installed, not how. This enables cross-distro restore.

### 5. **Configuration Continuity**
Backed-up config files (smb.conf, daemon.json, etc.) are preserved across restores, even when switching distributions.

## Extensibility

### Adding a New Feature Category

See `SCHEMA.md` for the full process, but in summary:

1. Create `my-feature.json` with the structure (Debian/FreeBSD/Arch sections)
2. Add entry to `MANIFEST.json`
3. Commit and push
4. System automatically detects and offers it in the UI

### Adding Support for Ubuntu, Linux Mint, Rocky, CentOS, etc.

All of these can use the Debian-based package names (or with slight tweaks). Just add an entry to each category JSON:

```json
{
  "debian": { ... },
  "ubuntu": { ... },           // New
  "ubuntu-server": { ... },    // More specific variant
  "freebsd": { ... },
  "arch": { ... }
}
```

Then update `MANIFEST.json` to list these as supported editions.

### Community-Contributed Distributions

A developer could create a standalone repository:

```
freedomnas-profiles-openbsd/
├── packages/
│   ├── MANIFEST.json (adds openbsd to editions)
│   ├── core.json
│   ├── samba-cifs.json
│   └── ...
```

This can be merged into the main project or distributed as a separate module.

## Configuration Schema

See `SCHEMA.md` for the complete JSON schema and `packages.yaml` format.

## Troubleshooting

### "Package not found" error during install

**Cause:** Package name doesn't exist in the distro's repository  
**Fix:** Edit the category JSON with the correct package name, test, commit, push

### Restore on different distro fails

**Cause:** Config file paths differ (e.g., `/etc/` on Debian vs `/usr/local/etc/` on FreeBSD)  
**Fix:** The backup manager automatically handles common path mappings. For edge cases, manually restore configs.

### New category doesn't appear in installer

**Cause:** `MANIFEST.json` not updated  
**Fix:** Ensure the category is listed in `MANIFEST.json` with the correct filename

## Contributing

To contribute a new category or distro support:

1. Fork the `freedomnas-profiles` repository on Codeberg
2. Add/modify JSON files
3. Test on your target distro
4. Submit a PR with details about what you added

See `CONTRIBUTING.md` in the main repository for more details.

## License

Mozilla Public License v2.0 (same as FreedomNAS)

## Links

- **GitHub**: https://codeberg.org/sarahmeow86/freedomnas-profiles
- **Issues**: https://codeberg.org/sarahmeow86/freedomnas-profiles/issues
- **Schema docs**: `SCHEMA.md` (in this directory)
