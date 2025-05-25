# API Reference

## 🎛️ Command Line Interface

### Synopsis
```bash
debian_upgrade.sh [OPTIONS]
```

### Options

#### `-h, --help`
Display help information and exit.
```bash
debian_upgrade.sh --help
```

#### `-v, --version`
Show current Debian version information.
```bash
debian_upgrade.sh --version
# Output: Debian 11 (bullseye) [stable]
```

#### `-c, --check`
Check for available upgrades without performing them.
```bash
debian_upgrade.sh --check
```

#### `-d, --debug`
Enable debug mode with verbose logging.
```bash
debian_upgrade.sh --debug
```

#### `--fix-only`
Perform system repairs without upgrading.
```bash
debian_upgrade.sh --fix-only
```

#### `--force`
Skip confirmation prompts and run automatically.
```bash
debian_upgrade.sh --force
```

## 🔧 Internal Functions

### System Detection Functions

#### `get_current_version()`
**Purpose**: Detect current Debian version
**Returns**: Version number (e.g., "11")
**Usage**: Internal function for version detection

#### `get_version_info(version)`
**Purpose**: Get version codename and status
**Parameters**: 
- `version` - Debian version number
**Returns**: "codename|status" format
**Example**: `get_version_info "11"` returns "bullseye|stable"

#### `detect_vps_environment()`
**Purpose**: Detect VPS/virtualization environment
**Returns**: 0 if VPS detected, 1 if physical
**Sets**: Global variable with VPS type

### Mirror Management Functions

#### `select_mirror()`
**Purpose**: Choose optimal mirror based on location
**Returns**: Mirror URL
**Logic**: 
1. Detect geographic location
2. Test mirror connectivity
3. Select fastest available

#### `update_sources_list(version, codename)`
**Purpose**: Update APT sources configuration
**Parameters**:
- `version` - Target Debian version
- `codename` - Target Debian codename
**Side Effects**: Modifies /etc/apt/sources.list

### Upgrade Functions

#### `progressive_upgrade(phase)`
**Purpose**: Perform staged upgrade
**Parameters**:
- `phase` - "minimal"|"safe"|"full"
**Returns**: 0 on success, 1 on failure

#### `verify_upgrade(expected_version)`
**Purpose**: Verify upgrade completed successfully
**Parameters**:
- `expected_version` - Expected Debian version
**Returns**: 0 if verified, 1 if failed

### Utility Functions

#### `log_info(message)`
**Purpose**: Display informational message
**Parameters**: 
- `message` - Text to display
**Output**: Colored output with timestamp

#### `log_error(message)`
**Purpose**: Display error message
**Parameters**: 
- `message` - Error text to display
**Output**: Red colored error message

#### `enhanced_apt_cleanup()`
**Purpose**: Comprehensive APT cache and lock cleanup
**Side Effects**: 
- Removes lock files
- Clears package cache
- Resets APT state

## 🔄 Exit Codes

| Code | Meaning | Description |
|------|---------|-------------|
| 0 | Success | Operation completed successfully |
| 1 | General Error | Generic error condition |
| 2 | Invalid Usage | Incorrect command line arguments |
| 3 | System Check Failed | Pre-upgrade checks failed |
| 4 | Network Error | Network connectivity issues |
| 5 | Package Error | APT/package management errors |
| 6 | Permission Error | Insufficient privileges |
| 7 | Verification Failed | Post-upgrade verification failed |

## 📁 File Locations

### Configuration Files
- **Main Script**: `/usr/local/bin/debian_upgrade.sh`
- **Symlink**: `/usr/local/bin/debian-upgrade`
- **Backup Directory**: `/var/backups/debian-upgrade-TIMESTAMP/`

### Log Files
- **Debug Output**: Console output only
- **System Logs**: `/var/log/apt/` (APT operations)
- **Backup Info**: `/tmp/debian_upgrade_backup_path`

### Temporary Files
- **Download Cache**: `/tmp/` (temporary files)
- **APT Cache**: `/var/cache/apt/`
- **Package Lists**: `/var/lib/apt/lists/`

## 🌐 Environment Variables

### Script Behavior
```bash
# Enable debug mode
export DEBUG=1
debian_upgrade.sh

# Force mode
export FORCE=1
debian_upgrade.sh

# Custom mirror
export DEBIAN_MIRROR="http://custom.mirror.com/debian"
debian_upgrade.sh
```

### System Integration
```bash
# Use specific sudo command
export USE_SUDO="doas"

# Custom backup directory
export BACKUP_DIR="/custom/backup/path"
```

## 🔌 Integration Examples

### Automated Deployment
```bash
#!/bin/bash
# deployment.sh

# Pre-upgrade snapshot
create_snapshot

# Run upgrade
if debian_upgrade.sh --force; then
    echo "Upgrade successful"
    verify_services
else
    echo "Upgrade failed, rolling back"
    restore_snapshot
fi
```

### Monitoring Integration
```bash
#!/bin/bash
# monitoring.sh

# Check for available upgrades
if debian_upgrade.sh --check | grep -q "可升级到"; then
    send_notification "Debian upgrade available"
fi
```

### Batch Processing
```bash
#!/bin/bash
# batch_upgrade.sh

for server in server1 server2 server3; do
    echo "Upgrading $server"
    ssh $server "debian_upgrade.sh --force"
done
```

## 🛡️ Error Handling

### Exception Handling
The script uses comprehensive error handling:
```bash
set -e  # Exit on error
trap 'handle_error $?' ERR
```

### Recovery Mechanisms
- Automatic backup restoration
- Service restart procedures
- Configuration validation
- Dependency resolution

### Logging Strategy
- Timestamped messages
- Severity levels (INFO, WARNING, ERROR)
- Debug mode for troubleshooting
- Structured output format

## 🔒 Security Considerations

### Privilege Requirements
- Requires `sudo` or root access
- Validates permissions before execution
- Uses minimal required privileges

### Data Safety
- Automatic configuration backup
- Non-destructive operations when possible
- Verification before critical changes
- Recovery procedures available

### Network Security
- GPG signature verification
- Secure mirror selection
- HTTPS preferred where available
- DNS validation
```
### Linode
- Use NodeBalancer for load balancing
- Leverage backup service integration
- Utilize Object Storage for backups
- Monitor with Longview
