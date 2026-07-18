# How to Add a New Distribution

Welcome! This guide will help you add support for a new Linux or BSD distribution to FreedomNAS.

## Structure of an OS Profile

Each distribution is defined by a JSON file containing the native commands for common operations. FreedomNAS's universal engine translates abstract actions into the commands specific to your OS.

## Step 1: Create the Profile File

1. Create a new `{distro_name}.json` file in the `freedomnas-profiles/` directory
2. Use the minimal template below as a starting point

### Minimal Template

```json
{
  "os_name": "Your Distribution Name",
  "os_family": "linux",  // or "bsd"
  "os_version": "version_info",

  "users": {
    "create": "command_to_create_user",
    "delete": "command_to_delete_user",
    "set_password": "command_to_set_password",
    "list": "command_to_list_users",
    "get_user_info": "command_to_get_user_info",
    "add_to_group": "command_to_add_user_to_group",
    "remove_from_group": "command_to_remove_user_from_group"
  },

  "services": {
    "start": "command_to_start_service",
    "stop": "command_to_stop_service",
    "restart": "command_to_restart_service",
    "enable": "command_to_enable_service",
    "disable": "command_to_disable_service",
    "status": "command_to_check_service_status",
    "is_enabled": "command_to_check_if_service_is_enabled",
    "reload": "command_to_reload_service",
    "daemon_reload": "command_to_reload_daemon_config"
  },

  "packages": {
    "update_cache": "command_to_update_package_cache",
    "install": "command_to_install_package",
    "remove": "command_to_remove_package",
    "upgrade": "command_to_upgrade_all_packages"
  },

  "zfs": {
    "pool_create": "zpool command syntax for your OS",
    "pool_import": "zpool import command",
    "pool_list": "zpool list command"
  },

  "system": {
    "hostname_set": "command_to_set_hostname",
    "reboot": "command_to_reboot_system",
    "shutdown": "command_to_shutdown_system",
    "uptime": "command_to_check_uptime",
    "uname": "command_to_get_system_info"
  }
}
```

## Step 2: Complete the Categories

Add support for the following categories (if relevant to your distribution):

- **network**: Commands to configure networking
- **samba**: Commands for SMB/CIFS
- **nfs**: Commands for NFS
- **btrfs**: Commands for the Btrfs filesystem (if supported)
- **grub_btrfs**: Commands for GRUB with Btrfs snapshots

## Step 3: Parameter Placeholders

Use `{parameter_name}`-style placeholders in commands. Common examples:

- `{service_name}`: Service name
- `{package_name}`: Package name
- `{username}`: Username
- `{groups}`: List of groups
- `{hostname}`: Hostname
- `{ip}`: IP address
- `{interface}`: Network interface name
- `{pool_name}`: ZFS pool name
- `{dataset}`: ZFS dataset

## Step 4: Test the Profile

### Manual Test

```python
from freedomnas_core.engine import FreedomNASEngine

# Create the engine with the new profile
engine = FreedomNASEngine(os_override="your_distro")

# Test a few commands
cmd = engine.get_command("services", "start", service_name="samba")
print(f"Start Samba: {cmd}")

cmd = engine.get_command("packages", "install", package_name="vim")
print(f"Install vim: {cmd}")

# Check OS info
print(engine.get_os_info())
```

### Real Execution

```python
# For production systems, test with actual execution
try:
    stdout, stderr = engine.execute("packages", "update_cache", timeout=60)
    print(f"Update cache completed")
except Exception as e:
    print(f"Error: {e}")
```

## Step 5: Submit Your Contribution

1. Verify that your JSON profile is valid:
   ```bash
   python -m json.tool {distro_name}.json
   ```

2. Add a comment in the JSON file or in a README specific to your distro

3. Create a Pull Request with:
   - The new `{distro_name}.json` file
   - A note in `CONTRIBUTING.md` linking to where to test it
   - Example test cases (optional but much appreciated)

## Command Guidelines

### Security

- **Do NOT use the shell** unless absolutely necessary
- Use command-line parameters, not shell pipes
- Avoid interpolating untrusted strings
- We prefer commands that fail loudly over ones that fail silently

### Compatibility

- Use commands that exist in the minimum supported version of the distro
- If a command changes between versions, use the one from the most stable version
- Document version requirements in the comment

### Format

- One command per action
- If multiple commands are needed, use a JSON array: `["cmd1", "cmd2"]`
- Keep action names consistent with the other profiles

## Examples

### Generic Linux

```json
"packages": {
  "update_cache": "apt-get update",
  "install": "apt-get install -y {package_name}",
  "remove": "apt-get remove -y {package_name}",
  "upgrade": "apt-get dist-upgrade -y"
}
```

### BSD

```json
"packages": {
  "update_cache": "pkg update",
  "install": "pkg install -y {package_name}",
  "remove": "pkg remove -y {package_name}",
  "upgrade": "pkg upgrade -y"
}
```

### Multiple Commands

```json
"zfs": {
  "pool_create": [
    "zpool create -o ashift=12 {pool_name} {vdev_type}",
    "zfs set recordsize=1M {pool_name}"
  ]
}
```

## Support

- **Questions?** Open a discussion in the repository
- **Bugs in a profile?** File an issue with the command that fails
- **Improvements?** Reach out to coordinate changes

Thank you for contributing to FreedomNAS! 🎉
