# FreedomNAS Package Management Schema

## Overview

FreedomNAS uses a modular, category-based package system to support multiple Linux distributions (Debian, FreeBSD, Arch). This makes it easy to:

- Add support for new distributions
- Switch editions during setup
- Restore full functionality after disaster recovery
- Allow community-contributed configurations

## Directory Structure

```
freedomnas-profiles/packages/
├── MANIFEST.json           ← Package categories and metadata
├── SCHEMA.md              ← This file
├── core.json              ← Essential packages (required)
├── samba-cifs.json        ← SMB/CIFS file sharing (optional)
├── nfs.json               ← NFS file sharing (optional)
├── containers.json        ← Docker/Podman (optional)
└── virtualization.json    ← KVM/Bhyve (optional)
```

## Package JSON Format

Each category file follows this structure:

```json
{
  "category": "samba-cifs",
  "description": "SMB/CIFS file sharing — Windows-compatible network shares",
  "debian": {
    "packages": ["samba", "samba-common-bin"],
    "services": ["smbd", "nmbd"],
    "config_paths": ["/etc/samba/smb.conf"]
  },
  "freebsd": {
    "packages": ["samba416"],
    "services": ["samba"],
    "config_paths": ["/usr/local/etc/smb.conf"]
  },
  "arch": {
    "packages": ["samba"],
    "services": ["smbd", "nmbd"],
    "config_paths": ["/etc/samba/smb.conf"]
  }
}
```

### Fields

- **category** — Unique identifier (kebab-case, must match filename)
- **description** — Human-readable category description
- **debian/freebsd/arch** — OS-specific configuration:
  - **packages** — List of package names to install (OS-native package manager)
  - **services** — List of systemd/rc.conf services to enable
  - **config_paths** — Paths to configuration files (for backup/restore)

## Installer Configuration Storage

The installer/WebUI stores a `packages.yaml` file in the system:

**Path:**
- Debian/Arch: `/etc/freedomnas/packages.yaml`
- FreeBSD: `/usr/local/etc/freedomnas/packages.yaml`

**Format:**
```yaml
version: "4.0.0"
edition: debian              # or freebsd, arch
installed_categories:
  - id: core
    status: installed
    installed_date: "2026-05-22T14:30:00Z"
    version: "4.0.0"

  - id: samba-cifs
    status: installed
    installed_date: "2026-05-22T14:45:00Z"
    version: "4.0.0"
    config_backup: "/var/backups/freedomnas/samba-cifs-2026-05-22.tar.gz"

  - id: nfs
    status: available
    version: "4.0.0"
    
  - id: containers
    status: installed
    installed_date: "2026-05-23T09:15:00Z"
    version: "4.0.0"
    config_backup: "/var/backups/freedomnas/containers-2026-05-23.tar.gz"

  - id: virtualization
    status: available
    version: "4.0.0"
```

## Disaster Recovery Flow

When restoring from backup:

1. **Detect** — Check the `packages.yaml` backup to see which categories were installed
2. **Load Manifest** — Read `MANIFEST.json` to find the package definitions
3. **Determine Edition** — Auto-detect the current OS (or prompt user to switch)
4. **Install Packages** — For each installed category, install the OS-specific packages
5. **Restore Configs** — Extract backed-up configurations to their original paths
6. **Enable Services** — Start and enable the services for each category
7. **Verify** — Check that all services are running correctly

## Adding a New Category

To add a new optional category (e.g., "backup-tools"):

1. Create `backup-tools.json` with the same structure:
```json
{
  "category": "backup-tools",
  "description": "Backup and disaster recovery tools",
  "debian": { "packages": [...], "services": [...], "config_paths": [...] },
  "freebsd": { "packages": [...], "services": [...], "config_paths": [...] },
  "arch": { "packages": [...], "services": [...], "config_paths": [...] }
}
```

2. Update `MANIFEST.json`:
```json
{
  "id": "backup-tools",
  "name": "Backup Tools",
  "description": "Backup and disaster recovery tools",
  "required": false,
  "file": "backup-tools.json"
}
```

3. Commit and push to Codeberg
4. WebUI will automatically detect and offer the new category

## Adding Support for a New Distribution

To add Debian-based distros (Ubuntu, Linux Mint, etc.) or other variants:

1. Add the distribution name to each category JSON (e.g., "ubuntu", "mint")
2. Use identical or slightly adjusted package names based on the distro
3. Update `MANIFEST.json` to list the new edition
4. Test on the target distribution before merging

Example (adding Ubuntu):
```json
{
  "debian": { ... },      // Debian
  "ubuntu": {             // Ubuntu (same packages, same format)
    "packages": ["zfsutils-linux", ...],
    "services": ["ssh", ...],
    "config_paths": [...]
  },
  "freebsd": { ... },
  "arch": { ... }
}
```

## Backup/Restore Implementation

**Installer/WebUI Responsibility:**

1. **On Installation:**
   - Record selected categories in `packages.yaml`
   - Tar up configuration files for each category
   - Store in `/var/backups/freedomnas/` with timestamps

2. **On Backup:**
   - Include `packages.yaml` (identifies what to restore)
   - Include all backed-up configuration archives

3. **On Restore:**
   - Read `packages.yaml` from backup
   - For each installed category, read the JSON package definition
   - Install packages using the current OS's package manager
   - Extract configuration files from backups
   - Restart services

This allows users to:
- ✓ Switch from Debian to FreeBSD (or vice versa) and restore all functionality
- ✓ Restore on a fresh installation of any supported OS
- ✓ Upgrade/downgrade editions while keeping their data and configurations

## Example: Disaster Recovery Scenario

**Original Setup:**
- Debian Edition with Samba, NFS, and Containers

**Hardware Failure:**
- Install fresh Debian → restore from backup
  - ✓ All packages reinstalled
  - ✓ All configs restored
  - ✓ Services running
  
- OR install fresh FreeBSD → restore from Debian backup
  - ✓ FreeBSD versions of Samba, NFS, Containers installed
  - ✓ All configs restored (adapted to FreeBSD paths)
  - ✓ Services running
  
- OR install fresh Arch → restore from Debian backup
  - ✓ Arch versions installed
  - ✓ All configs restored
  - ✓ Services running

This makes FreedomNAS truly portable across distributions!
