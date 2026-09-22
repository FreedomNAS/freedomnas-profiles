# Contributing to freedomnas-profiles

Welcome! This repository holds the JSON translation layer that lets
FreedomNAS run identically on Debian, FreeBSD, Arch, and (soon) other
UNIX-like systems without a single line of OS-specific Python. If you can
write a shell command for your OS, you can contribute here — no Python
required.

Two independent things live in this repo, and contributing to them is a
different process:

| You want to... | Where | Guide |
|-----------------|-------|-------|
| Add/fix the **commands** FreedomNAS runs (create a user, list ZFS pools, restart Samba, ...) for an OS | `os/`, `storage/`, `network/`, `shares/`, `users/`, `init/` | **This file** |
| Add/fix an **optional installable feature** (Samba, NFS, containers, ...) and which packages it needs | `packages/` | [`packages/README.md`](packages/README.md) + [`packages/SCHEMA.md`](packages/SCHEMA.md) |

This file covers the first track.

## Repository Layout

Profiles are split **per module**, not one file per OS — this is what lets
a contribution (yours!) touch only the file(s) relevant to what you're
changing, without stepping on anything else:

```
freedomnas-profiles/
├── os/                 Shared primitives no module owns: packages,
│   os-debian.json      bootloader, system info, os_name/os_family/
│   os-freebsd.json     os_version/init_system
│   os-arch.json
│   os-artix.json       ("exotic" edition, Phase 3 — see below)
│   os-void.json        ("exotic" edition, Phase 3 — see below)
├── storage/            zfs, media, zfs_properties
│   storage-<os>.json
├── network/            network
│   network-<os>.json
├── shares/              samba, nfs
│   shares-<os>.json
├── users/               users
│   users-<os>.json
├── init/                services (start/stop/enable/...), one file per
│   init-systemd.json    init system, shared across every OS that uses it
│   init-openrc.json
│   init-runit.json
│   init-s6.json
│   init-dinit.json
│   init-bsd_rc.json
├── installer/           How an edition gets *installed*: installer_meta,
│   installer-<os>.json  chroot, partitioning, rootpool, bootstrap, files.
│                         Read only by freedomnas-installer — add one if
│                         your OS should be installable, skip it if you
│                         only want FreedomNAS to *run* on it
├── assets/               Boot-chain binaries (vendored Clover, the
│                         zz-dracut-uki hook) and the boot-time scripts
│                         (firstboot.sh, supervisor.sh) — not something
│                         you'll usually touch; see assets/clover/README.md
│                         before ever changing anything here
└── packages/             Different track — see the table above
```

`engine.py` (in `freedomnas-core`) assembles the actual profile for a
running system at startup: load `os/os-<os>.json` as the base, merge in
every `<module>/<module>-<os>.json` fragment it finds, then merge in
`init/init-<init_system>.json`'s `services` section last. Each fragment
owns distinct top-level category keys, so there's nothing to resolve — your
new fragment just gets picked up automatically.

## Design Rules — Read This First

- **No branching logic.** A profile is pure data: `{action: "command string"}`.
  No `if`, no loops, no environment detection.
- **No side effects.** A profile doesn't execute anything — `engine.py`
  does, elsewhere, in a different repo.
- **One template variable per moving part.** `{username}`, `{package_name}`,
  `{service_name}`, etc. — see the reference table below.
- **`services` never appears outside `init/`.** Service start/stop/enable
  commands belong in the init profile for that init system, never in an
  OS or module fragment — this is what lets the same OS fragment work
  under different init systems.

## Adding a New OS

Say you want to add Alpine Linux.

### 1. Create the shared base fragment

`os/os-alpine.json` — the primitives no module owns:

```json
{
  "os_name": "Alpine",
  "os_family": "linux",
  "os_version": "3.18+",
  "init_system": "openrc",

  "packages": {
    "update_cache": "apk update",
    "install": "apk add {packages}",
    "remove": "apk del {packages}",
    "upgrade": "apk upgrade"
  },
  "bootloader": { "...": "fill in if Alpine needs one — see os-debian.json/os-freebsd.json for the two existing patterns (dracut+efibootmgr vs FreeBSD's native gptzfsboot/loader.efi)" },
  "system": {
    "hostname_set": "hostnamectl set-hostname {hostname}",
    "reboot": "reboot",
    "shutdown": "poweroff",
    "uptime": "uptime -p",
    "uname": "uname -a"
  }
}
```

### 2. Create a fragment in every module directory you can support

Not every module needs to be complete on day one — a partial contribution
(e.g. just `users/users-alpine.json` and `network/network-alpine.json`) is
genuinely useful and easy to review. Add `<module>-alpine.json` to whichever
of `storage/`, `network/`, `shares/`, `users/` you're able to fill in:

```json
// users/users-alpine.json
{
  "users": {
    "create": "adduser -D -u {uid} -G {groups} {username}",
    "delete": "deluser {username}",
    "set_password_stdin": "chpasswd",
    "list": "getent passwd | awk -F: '$3 >= 1000 && $3 < 65534'",
    "get_user_info": "getent passwd {username}",
    "add_to_group": "adduser {username} {group}",
    "remove_from_group": "delgroup {username} {group}"
  }
}
```

**Never add a `services` key here** — see Design Rules above.

### 3. Reuse or add an init profile

Alpine uses OpenRC, and `init/init-openrc.json` already exists — nothing to
do, just set `"init_system": "openrc"` in step 1's `os-alpine.json`.

If your OS uses an init system FreedomNAS doesn't support yet, add
`init/init-<name>.json` with just a `services` section — see any existing
`init/init-*.json` for the exact action set expected
(`start`/`stop`/`restart`/`enable`/`disable`/`status`/`is_enabled`/`reload`/`daemon_reload`/`list_managed`).

### 4. Validate your JSON

```bash
python3 -m json.tool os/os-alpine.json
python3 -m json.tool storage/storage-alpine.json   # for each fragment you added
```

### 5. Test against a real (or overridden) engine

This requires a `freedomnas-core` checkout as a sibling directory — see
that repo's `DEVELOPER_GUIDE.md` if you don't have one:

```python
from freedomnas.engine import FreedomNASEngine

engine = FreedomNASEngine(os_override="alpine")
print(engine.get_os_info())
print(engine.get_command("users", "create", username="test", uid=1001, gid=1001, groups="wheel"))
print(engine.get_command("packages", "install", packages="vim"))
```

`os_override` bypasses OS auto-detection, so you can develop and test an
Alpine profile from any machine.

!!! note "Two more things needed before Alpine is actually reachable"
    A profile alone doesn't make an OS selectable at runtime. That also
    needs: **(a)** two entries in `freedomnas-core`'s `engine.py` — the
    distribution's `/etc/os-release` `ID` in `_DISTRO_IDS` (this is the
    real gate for auto-detection) and its name in `SUPPORTED_OS`. It's
    Python, so it's a separate PR against the [`freedomnas-core`
    repository](https://codeberg.org/FreedomNAS/freedomnas-core). And
    **(b)** an `"alpine"` entry in each relevant `packages/*.json` category
    file (see the packages track above) if you want the optional features
    (Samba, NFS, ...) to be installable too.

    Gentoo, Artix and Void are worked, complete examples to copy from —
    profile, per-module fragments, package sections, installer fragment
    and engine entries, all in place.

!!! tip "Making the OS installable too"
    The fragments above make FreedomNAS *run* on an OS. To make
    `freedomnas-install` able to *install* it, add
    `installer/installer-<os>.json` as well — see
    [PROFILE_SPECIFICATION_v1.md](../freedomnas-specs/PROFILE_SPECIFICATION_v1.md#installer-profile-structure)
    for the schema, and copy `installer/installer-void.json` if your OS has
    no native bootstrapper reachable from other distros (it uses the rootfs
    tarball method, which needs only `curl` and `tar` on the installer
    host); `installer/installer-gentoo.json` is the same method applied to
    a stage3, with Portage's make.conf and binary host written as profile
    file contents. Then check the whole install resolves, without touching a disk:

    ```sh
    python3 tests/dryrun_smoke.py     # in freedomnas-installer
    sudo freedomnas-install --dry-run --mode clean --target <os>
    ```

### 6. Submit

Open a PR against `freedomnas-profiles` with your new/changed fragment
files. Mention in the description:

- Which module fragments you completed vs. left out
- What you tested it against (a real machine, a container, `os_override`
  only, ...)
- Whether you also opened a companion PR against `freedomnas-core` for
  `_DISTRO_IDS`/`SUPPORTED_OS`

A profiles-only PR without the engine entries is still valuable and
mergeable on its own: the profile can be exercised immediately with
`os_override`, and the engine side is two lines someone else can add.

## Adding Support for an Existing Module on a New OS You Use

Smaller version of the above: if Debian/FreeBSD/Arch profiles already
exist but, say, `shares/shares-<os>.json` for your OS has a command that's
wrong or missing an edge case, you only need to touch that one file. You
don't need to understand or test the other modules.

## Fixing or Extending an Existing Command

1. Find the owning fragment using the table in "Repository Layout" above
   (e.g. a Samba command lives in `shares/shares-<os>.json`, not `os/`).
2. Edit the command string. Keep the action name identical across every OS
   that has it — the engine looks up `category.action`, and a renamed key
   on only one OS silently breaks that OS.
3. If you're adding a brand new action, add it to the same category in
   *every* OS's fragment, even if only as a best-effort guess for OSes you
   can't test — leaving it out entirely means `engine.execute()` raises
   `CommandTranslationError` on that OS instead of failing more gracefully.

## Template Variable Reference

Placeholders use `{name}` and are substituted by `engine.get_command()`/`execute()`.
Common ones, by category:

| Variable | Used in | Example |
|----------|---------|---------|
| `{username}`, `{uid}`, `{gid}`, `{shell}`, `{groups}` | `users.create` | `admin`, `1000`, `1000`, `/bin/bash`, `sudo,samba` |
| `{group}` | `users.add_to_group`/`remove_from_group` | `samba` |
| `{service_name}` | `services.*` (init profiles only) | `smbd` |
| `{package_name}` or `{packages}` | `packages.install`/`remove` | `samba` / `samba samba-common-bin` |
| `{pool_name}`, `{dataset}`, `{snap_name}` | `zfs.*` | `rpool`, `rpool/ROOT/debian`, `pre-update-20260718` |
| `{ashift}`, `{compression}`, `{vdev_type}`, `{devices}` | `zfs.pool_create` | `12`, `lz4`, `mirror`, `/dev/disk/by-id/...` |
| `{keyfile_path}` | `zfs.pool_create_encrypted`/`load_key_file` | (transient tmpfs path, never a literal secret — see `freedomnas-core/keymgmt.py`) |
| `{device}`, `{mountpoint}` | `media.*` | `/dev/sdb1`, `/run/freedomnas/usbkey` |
| `{share_name}`, `{path}`, `{comment}`, `{acl}` | `samba.create_share` | `Documents`, `/mnt/datapool/docs`, `User docs`, `Everyone:R` |
| `{clients}`, `{options}` | `nfs.export_add` | `192.168.1.0/24`, `rw,sync,no_subtree_check` |
| `{conn_name}`, `{ip}`, `{cidr}`, `{gateway}`, `{dns}` | `network.set_static_ip` | `eth0`, `192.168.1.50`, `24`, `192.168.1.1`, `1.1.1.1 8.8.8.8` |
| `{hostname}`, `{timezone}` | `system.*` | `freedomnas`, `Europe/Rome` |

Keep new variable names consistent with existing ones for the same concept
— don't invent `{pkg}` when every other fragment uses `{package_name}`.

## Command Guidelines

### Security

- **Never rely on a shell pipeline unless the action genuinely needs one**
  (e.g. `apt list --upgradable | tail -n +2`). `engine.py` only invokes
  `shell=True` when it detects shell metacharacters in *your* command
  string — so a command with an unnecessary pipe silently opts into a
  larger attack surface than a plain argv command.
- Never put a placeholder inside quotes of its own. The engine quotes every
  value into exactly one argument, and a quote in the value would close
  yours. To make a value part of a larger word, concatenate:
  `{path}' '{clients}'('{options}')'`, `"root=ZFS="{dataset}" rw"`.
- A variable that carries several arguments (`{devices}`, `{package_list}`,
  an optional flag like `{force}`) must be listed in its category's
  `"multi_args"`; everything else is one argument, even when empty.
- Prefer commands that fail loudly (non-zero exit, clear stderr) over ones
  that silently no-op.

### Compatibility

- Use commands available in the **minimum supported version** of the OS.
- If a command's flags changed between versions, use the most stable/widely
  available form and note the version requirement in a `maintainer_note`
  field (see `os-arch.json`/`os-artix.json`/`os-void.json` for the
  convention — community-maintained profiles use this to flag things that
  need real-world validation).

### Format

- One command per action, as a plain string.
- If an action genuinely needs multiple sequential commands, use a JSON
  array: `["cmd1", "cmd2"]` — `engine.execute()` runs each in order and
  returns the last result.
- Action names must match exactly across every OS's fragment for the same
  category (see "Fixing or Extending an Existing Command" above).

## Examples

### A package manager block (Alpine)

```json
"packages": {
  "update_cache": "apk update",
  "install": "apk add {packages}",
  "remove": "apk del {packages}",
  "upgrade": "apk upgrade"
}
```

### A multi-step action

```json
"zfs": {
  "pool_create": [
    "zpool create -o ashift=12 {pool_name} {vdev_type} {devices}",
    "zfs set recordsize=1M {pool_name}"
  ]
}
```

## Support

- **Questions?** Open a discussion or issue on
  [codeberg.org/FreedomNAS/freedomnas-profiles](https://codeberg.org/FreedomNAS/freedomnas-profiles).
- **A command fails on your system?** File an issue with the exact command
  (`engine.get_command(...)` output, not just the action name), your
  OS/version, and the error.
- **Not sure which file owns a category?** See the table in "Repository
  Layout" above, or ask in an issue before writing anything — happy to
  point you at the right file.

Thank you for contributing to FreedomNAS!
