# Installation Guide

## 🚀 Quick Installation

### One-Line Install (Recommended)
```bash
curl -fsSL https://raw.githubusercontent.com/everett7623/debian-auto-upgrade/main/install.sh | bash
```

### Manual Installation
```bash
# Download the script
wget https://raw.githubusercontent.com/everett7623/debian-auto-upgrade/main/debian_upgrade.sh

# Make executable
chmod +x debian_upgrade.sh

# Optional: Move to system PATH
sudo mv debian_upgrade.sh /usr/local/bin/
sudo ln -s /usr/local/bin/debian_upgrade.sh /usr/local/bin/debian-upgrade
```

## 📋 System Requirements

### Minimum Requirements
- Debian 8 (Jessie) or higher
- 2GB available disk space
- 512MB available RAM
- Internet connection
- `sudo` privileges or root access

### Recommended Requirements
- Debian 10+ for best compatibility
- 4GB+ available disk space
- 1GB+ available RAM
- Stable high-speed internet

## 🔧 Dependencies

The script automatically installs required dependencies, but you can pre-install them:

```bash
sudo apt update
sudo apt install -y curl wget gnupg debian-archive-keyring
```

## 🛠️ VPS-Specific Setup

### AWS EC2
```bash
# No special setup required
# Ensure security groups allow SSH
```

### DigitalOcean
```bash
# Enable console access in control panel
# Consider enabling monitoring
```

### Vultr
```bash
# Ensure console access is available
# Consider enabling IPv6 if needed
```

### Linode
```bash
# Enable Lish console access
# Review firewall settings
```

## ✅ Verification

After installation, verify with:
```bash
debian_upgrade.sh --version
debian_upgrade.sh --check
```
