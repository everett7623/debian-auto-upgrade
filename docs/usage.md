# Usage Guide

## 🎯 Basic Usage

### Check Available Upgrades
```bash
debian_upgrade.sh --check
```

### Perform Upgrade
```bash
# Interactive upgrade
debian_upgrade.sh

# Force upgrade (no prompts)
debian_upgrade.sh --force
```

### System Repair Only
```bash
debian_upgrade.sh --fix-only
```

## 🔧 Advanced Options

### Debug Mode
```bash
debian_upgrade.sh --debug
```
Enables verbose logging for troubleshooting.

### Help Information
```bash
debian_upgrade.sh --help
```

## 📊 Understanding Output

### Status Indicators
- ✅ **Success** - Operation completed successfully
- ⚠️ **Warning** - Potential issue, but continuing
- ❌ **Error** - Critical error, operation stopped
- ℹ️ **Info** - General information

### Log Levels
- `[INFO]` - General information
- `[SUCCESS]` - Successful operations
- `[WARNING]` - Non-critical issues
- `[ERROR]` - Critical errors
- `[DEBUG]` - Detailed debugging information

## 🔄 Upgrade Process

### Phase 1: Pre-upgrade Checks
- System compatibility verification
- Disk space and memory checks
- Network connectivity test
- VPS environment detection

### Phase 2: Backup and Preparation
- Configuration files backup
- Package list export
- Mirror selection and optimization
- APT cache cleanup

### Phase 3: Staged Upgrade
1. **Minimal Upgrade** - Update existing packages
2. **Safe Upgrade** - Upgrade without removing packages
3. **Full Upgrade** - Complete distribution upgrade

### Phase 4: Post-upgrade Verification
- Version verification
- Service status checks
- Network connectivity test
- System health validation

## 🎛️ Configuration

### Mirror Selection
The script automatically selects mirrors based on location, but you can influence this:

```bash
# For Chinese users, it will automatically use:
# - Tsinghua University mirror
# - USTC mirror
# - NetEase mirror

# For other regions, it uses geographically appropriate mirrors
```

### Backup Location
Backups are stored in `/var/backups/debian-upgrade-TIMESTAMP/`

## 📝 Best Practices

### Before Upgrading
1. Create system snapshot (VPS)
2. Backup important data
3. Test in development environment
4. Schedule during maintenance window
5. Ensure console access

### During Upgrade
1. Monitor progress logs
2. Don't interrupt the process
3. Keep console access ready
4. Be patient - upgrades take time

### After Upgrade
1. Verify system functionality
2. Test critical services
3. Update custom configurations
4. Monitor system stability
5. Plan next upgrade cycle
