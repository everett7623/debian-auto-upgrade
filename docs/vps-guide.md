# VPS Deployment Guide

## 🌐 Supported VPS Providers

### ✅ Fully Tested Providers

#### AWS EC2
- **Supported**: All instance types
- **Special Features**: 
  - Automatic instance type detection
  - EBS optimization
  - Security group considerations
- **Console Access**: EC2 Instance Connect / Session Manager

#### DigitalOcean
- **Supported**: All droplet sizes
- **Special Features**:
  - Automatic region detection
  - Monitoring integration
  - Volume optimization
- **Console Access**: Recovery console via control panel

#### Vultr
- **Supported**: All instance types
- **Special Features**:
  - High-performance SSD optimization
  - Location-based mirror selection
  - IPv6 support
- **Console Access**: Web-based console

#### Linode
- **Supported**: All Linode plans
- **Special Features**:
  - Automatic backup integration
  - Network helper compatibility
  - Longview monitoring support
- **Console Access**: Lish console

### ⚠️ Partially Tested Providers

#### Hetzner Cloud
- **Status**: Community tested
- **Known Issues**: None reported
- **Console Access**: VNC console

#### OVH/OVHcloud
- **Status**: Limited testing
- **Known Issues**: Custom kernel configurations
- **Console Access**: IPMI/VNC

#### Contabo
- **Status**: Community feedback positive
- **Known Issues**: Slower network mirrors
- **Console Access**: Web console

## 🔧 VPS-Specific Optimizations

### OpenVZ Containers
```bash
# Automatic detection and fixes:
# - Limited /proc filesystem
# - Memory constraints
# - Kernel module limitations
# - Network configuration quirks
```

**Special Handling**:
- Modified package selection
- Alternative service management
- Network configuration validation
- Resource usage optimization

### KVM/Xen Virtualization
```bash
# Full virtualization support:
# - Complete kernel access
# - All package compatibility
# - Standard service management
# - Normal network configuration
```

**Optimizations**:
- Virtio driver optimization
- Memory balloon handling
- CPU scaling awareness
- Network interface bonding

### Docker Containers
```bash
# Limited support with caveats:
# - System service limitations
# - Init system constraints
# - Network namespace issues
# - Storage overlay complications
```

**Requirements**:
- Privileged container mode
- Host volume mounts
- Specific capability sets

## 📋 Pre-Deployment Checklist

### Essential Preparations
- [ ] **Console Access** - Verify backup access method
- [ ] **System Snapshot** - Create recovery point
- [ ] **Service Inventory** - Document running services
- [ ] **Network Config** - Record current settings
- [ ] **Backup Verification** - Test restore procedures

### VPS Provider Specific
- [ ] **AWS**: Check IAM permissions, security groups
- [ ] **DigitalOcean**: Enable console access, verify SSH keys
- [ ] **Vultr**: Activate console, review firewall rules
- [ ] **Linode**: Configure Lish access, backup settings

### Network Considerations
- [ ] **Firewall Rules** - Document current configuration
- [ ] **DNS Settings** - Record custom configurations
- [ ] **SSL Certificates** - Note renewal requirements
- [ ] **Load Balancers** - Health check configurations

## 🚀 Deployment Strategies

### Single Server Upgrade
```bash
# Basic upgrade process
1. Create snapshot
2. Run upgrade script
3. Verify functionality
4. Test services
5. Monitor stability
```

### Blue-Green Deployment
```bash
# Zero-downtime strategy
1. Clone production server
2. Upgrade clone server
3. Test clone thoroughly
4. Switch traffic to clone
5. Keep original as backup
```

### Rolling Updates
```bash
# For server clusters
1. Remove server from load balancer
2. Upgrade individual server
3. Test and verify
4. Add back to load balancer
5. Repeat for next server
```

## 🔧 Provider-Specific Configuration

### AWS EC2 Optimization
```bash
# Instance metadata service
curl -s http://169.254.169.254/latest/meta-data/instance-type

# EBS optimization
echo 'APT::Acquire::Retries "3";' > /etc/apt/apt.conf.d/80retries
```

### DigitalOcean Optimization
```bash
# Droplet agent compatibility
systemctl status droplet-agent

# Monitoring integration
apt-get install -y do-agent
```

### Vultr Optimization
```bash
# High-performance networking
echo 'net.core.rmem_max = 134217728' >> /etc/sysctl.conf
echo 'net.core.wmem_max = 134217728' >> /etc/sysctl.conf
```

## 🛡️ Security Considerations

### SSH Hardening
```bash
# Backup SSH config before upgrade
cp /etc/ssh/sshd_config /root/sshd_config.backup

# Key-based authentication only
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
```

### Firewall Configuration
```bash
# Document current rules
iptables-save > /root/iptables.backup

# Ensure SSH access remains
ufw allow 22/tcp
```

### VPS Provider Security Features
- **AWS**: Security Groups, NACLs, WAF
- **DigitalOcean**: Cloud Firewalls, VPC
- **Vultr**: Firewall Groups, Private Networks
- **Linode**: Cloud Firewalls, VLANs

## 📊 Performance Monitoring

### Resource Usage During Upgrade
```bash
# Monitor system resources
watch -n 5 'free -h && df -h && uptime'

# Network usage
iftop -i eth0

# Disk I/O
iotop
```

### Post-Upgrade Verification
```bash
# Service status check
systemctl --failed

# Network connectivity
ping -c 3 google.com

# Disk health
df -h && mount | column -t
```

## 🔄 Rollback Procedures

### VPS Snapshot Restore
```bash
# AWS EC2
aws ec2 create-snapshot --volume-id vol-xxxxxxxx
aws ec2 restore-snapshot-from-recycle-bin --snapshot-id snap-xxxxxxxx

# DigitalOcean
doctl compute droplet-action snapshot --snapshot-name "pre-upgrade"
doctl compute droplet-action restore --image-id xxxxxxxx

# Vultr
# Use web interface or API to restore snapshot
```

### Manual Rollback
```bash
# Restore from backup
cp /var/backups/debian-upgrade-*/sources.list /etc/apt/
apt update && apt install --reinstall $(cat /var/backups/debian-upgrade-*/package-selections.txt)
```

## 📞 Emergency Procedures

### Lost SSH Access
1. **Use VPS Console** - Log in via provider's web console
2. **Check Network Config** - Verify IP and routing
3. **Restart SSH Service** - `systemctl restart ssh`
4. **Check Firewall** - Ensure port 22 is open

### Boot Issues
1. **Boot into Rescue Mode** - Via VPS control panel
2. **Mount Filesystems** - Access system files
3. **Chroot Environment** - `chroot /mnt/root`
4. **Repair System** - Fix configuration issues

### Service Failures
```bash
# Critical service restart
systemctl restart networking
systemctl restart ssh
systemctl restart systemd-resolved

# Check service logs
journalctl -u servicename --since "1 hour ago"
```

## 📈 Best Practices Summary

### Before Upgrade
1. Create comprehensive backup strategy
2. Test upgrade on identical staging environment
3. Document all customizations
4. Prepare rollback procedures
5. Schedule during low-traffic periods

### During Upgrade
1. Monitor progress continuously
2. Keep console access ready
3. Don't interrupt the process
4. Be prepared for extended downtime
5. Have communication plan ready

### After Upgrade
1. Thoroughly test all services
2. Monitor system performance
3. Verify security configurations
4. Update monitoring/alerting
5. Document lessons learned

## 🎯 Provider-Specific Tips

### AWS EC2
- Use Elastic IPs to maintain connectivity
- Consider Auto Scaling Group updates
- Leverage Systems Manager for automation
- Monitor with CloudWatch

### DigitalOcean
- Use floating IPs for flexibility
- Leverage Spaces for backups
- Utilize monitoring and alerting
- Consider load balancer health checks

### Vultr
- Take advantage of block storage
- Use private networking for security
- Leverage startup scripts for automation
- Monitor with external tools
