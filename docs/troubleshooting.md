# Troubleshooting Guide

## 🚨 Common Issues

### APT Lock Errors
**Symptom**: "Could not get lock /var/lib/dpkg/lock"
```bash
# Solution
debian_upgrade.sh --fix-only

# Manual fix
sudo rm /var/lib/dpkg/lock*
sudo rm /var/cache/apt/archives/lock
sudo dpkg --configure -a
```

### Network Connectivity Issues
**Symptom**: Cannot download packages
```bash
# Check connectivity
ping -c 3 deb.debian.org

# Test DNS
nslookup deb.debian.org

# Manual DNS fix
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
```

### Insufficient Disk Space
**Symptom**: "No space left on device"
```bash
# Check disk usage
df -h

# Clean up space
sudo apt clean
sudo apt autoremove
sudo rm -rf /tmp/*

# Check for large log files
sudo du -sh /var/log/*
```

### GPG Key Errors
**Symptom**: "NO_PUBKEY" or signature verification failed
```bash
# Automatic fix
debian_upgrade.sh --fix-only

# Manual fix
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys KEYID
```

## 🔄 VPS-Specific Issues

### SSH Connection Lost
**Solutions**:
1. Use VPS console/VNC access
2. Check network configuration:
   ```bash
   sudo systemctl status networking
   sudo ip addr show
   ```
3. Restart network service:
   ```bash
   sudo systemctl restart networking
   ```

### OpenVZ Container Issues
**Common problems**:
- Limited /proc filesystem
- Kernel limitations
- Memory constraints

**Solutions**:
```bash
# Check container type
systemd-detect-virt

# OpenVZ specific fixes are automatically applied
debian_upgrade.sh --debug
```

### Cloud-Init Conflicts
**Symptom**: Network configuration overridden
```bash
# Disable cloud-init network management
sudo touch /etc/cloud/cloud-init.disabled
```

## 🔍 Diagnostic Commands

### System Information
```bash
# Debian version
cat /etc/os-release
cat /etc/debian_version

# System resources
free -h
df -h
lscpu

# Network status
ip addr show
cat /etc/resolv.conf
```

### APT Status
```bash
# Check APT configuration
apt-config dump

# List repositories
cat /etc/apt/sources.list
ls /etc/apt/sources.list.d/

# Check for broken packages
sudo apt --fix-broken install
```

### Service Status
```bash
# Critical services
sudo systemctl status ssh
sudo systemctl status networking
sudo systemctl status systemd-resolved
```

## 🩺 Recovery Procedures

### Restore from Backup
```bash
# Find backup location
ls /var/backups/debian-upgrade-*

# Restore sources.list
sudo cp /var/backups/debian-upgrade-*/sources.list /etc/apt/

# Restore network config
sudo cp /var/backups/debian-upgrade-*/network/* /etc/network/
```

### Emergency System Repair
```bash
# Boot into rescue mode (VPS console)
# Mount filesystem
# Chroot into system
# Run repair commands

sudo apt update --fix-missing
sudo apt --fix-broken install
sudo dpkg --configure -a
```

### Rollback Strategies
1. **VPS Snapshot Restore** (recommended)
2. **Package downgrade** (limited)
3. **Clean reinstall** (last resort)

## 📞 Getting Help

### Information to Collect
```bash
# System info
uname -a
cat /etc/os-release
df -h && free -h

# Error logs
debian_upgrade.sh --debug > debug.log 2>&1

# Network info
ip route show
cat /etc/resolv.conf
```

### Where to Get Help
1. GitHub Issues: Detailed bug reports
2. Discussions: General questions
3. Email: Direct support
4. Community forums: Debian-specific help
```
