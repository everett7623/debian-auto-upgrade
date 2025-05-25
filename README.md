# Debian Auto Upgrade

> 🚀 Intelligent Debian system upgrade tool with VPS optimization, automatic error fixing, and progressive upgrade strategy

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Debian](https://img.shields.io/badge/debian-8%2B-red.svg)](https://www.debian.org/)
[![Bash](https://img.shields.io/badge/bash-4.0%2B-green.svg)](https://www.gnu.org/software/bash/)
[![Version](https://img.shields.io/badge/version-2.1-brightgreen.svg)](CHANGELOG.md)
[![GitHub stars](https://img.shields.io/github/stars/everett7623/debian-auto-upgrade.svg?style=social)](https://github.com/everett7623/debian-auto-upgrade/stargazers)

## 📖 Overview

A powerful automated upgrade script designed specifically for Debian systems, capable of safely upgrading systems from older versions to the latest release step by step. Specially optimized for VPS environments with robust error recovery and fault tolerance capabilities.

⚠️ **Important**: Debian 12 (Bookworm) is the current stable version. The script will warn users before upgrading to testing versions and requires explicit confirmation.

### ✨ Key Features

- 🔄 **Progressive Upgrades** - Safely upgrade from Debian 8 to the latest version step by step
- 🛡️ **Smart Version Control** - Prevents accidental upgrades to unstable versions
- 🛠️ **VPS Environment Optimization** - Automatic detection and fixing of VPS-specific issues
- 🌍 **Smart Mirror Selection** - Automatically choose optimal software sources based on geographic location
- 🔧 **Automatic System Repair** - Fix APT issues, dependency conflicts, and broken packages
- 📦 **Staged Upgrade Strategy** - Progressive upgrade approach to minimize failure risks
- 💾 **Complete Backup** - Automatic backup of critical configuration files before upgrade
- 📊 **Detailed Logging** - Colorized output with timestamps and debug mode
- 🔍 **System Verification** - Comprehensive system status validation before and after upgrade
- ⚠️ **Risk Assessment** - Clear warnings and confirmations for testing/unstable versions

## 🎯 Supported System Versions

| Source Version | Target Version | Status | Upgrade Safety | Notes |
|----------------|----------------|--------|----------------|-------|
| Debian 8 (Jessie) | Debian 9 (Stretch) | ✅ Supported | 🔒 Safe | Legacy upgrade |
| Debian 9 (Stretch) | Debian 10 (Buster) | ✅ Supported | 🔒 Safe | Legacy upgrade |
| Debian 10 (Buster) | Debian 11 (Bullseye) | ✅ Supported | 🔒 Safe | Stable upgrade |
| Debian 11 (Bullseye) | Debian 12 (Bookworm) | ✅ Supported | 🔒 Safe | Current stable |
| Debian 12 (Bookworm) | Debian 13 (Trixie) | ⚠️ Available | ⚠️ Risky | Testing version - requires explicit confirmation |

> **Recommendation**: For production systems, stay on Debian 12 (Bookworm) as it's the current stable release.

## 🚀 Quick Start

### One-line Installation

```bash
curl -fsSL https://raw.githubusercontent.com/everett7623/debian-auto-upgrade/main/install.sh | bash
```

### Manual Installation

```bash
# Download the script
wget https://raw.githubusercontent.com/everett7623/debian-auto-upgrade/main/debian_upgrade.sh

# Make it executable
chmod +x debian_upgrade.sh

# Run the upgrade
./debian_upgrade.sh
```

## 📋 Usage Guide

### Basic Commands

```bash
# Check current system and available upgrades
./debian_upgrade.sh --check

# Automatic system upgrade (stable versions only - recommended)
./debian_upgrade.sh --stable-only

# Show current version information
./debian_upgrade.sh --version

# Display help information
./debian_upgrade.sh --help
```

### Advanced Options

```bash
# Enable debug mode for troubleshooting
./debian_upgrade.sh --debug

# Fix system issues only (no upgrade)
./debian_upgrade.sh --fix-only

# Force upgrade (skip confirmation prompts)
./debian_upgrade.sh --force

# Allow upgrades to testing versions (not recommended for production)
./debian_upgrade.sh --allow-testing

# Combine options
./debian_upgrade.sh --stable-only --debug
```

### 🛡️ Safe Usage Patterns

**For Production Servers (Recommended):**
```bash
# Check what's available without upgrading
./debian_upgrade.sh --stable-only --check

# Upgrade only to stable versions
./debian_upgrade.sh --stable-only
```

**For Development/Testing:**
```bash
# Allow testing versions (requires explicit confirmation)
./debian_upgrade.sh --allow-testing

# Force upgrade for automation (be careful!)
./debian_upgrade.sh --force
```

## 🔧 Feature Details

### 🌐 Intelligent Mirror Selection

The script automatically selects optimal software source mirrors based on your geographic location:

- 🇨🇳 **China** - Tsinghua University, USTC, NetEase mirrors
- 🇺🇸 **United States** - US official mirrors
- 🇬🇧 **United Kingdom** - UK official mirrors
- 🇩🇪 **Germany** - German official mirrors
- 🇯🇵 **Japan** - Japanese official mirrors

### 🛠️ VPS Environment Adaptation

Automatically detects and fixes common VPS issues:

- OpenVZ, KVM, Xen, VMware virtualization environments
- AWS EC2, Alibaba Cloud, Tencent Cloud servers
- DNS configuration problems
- Timezone and Locale settings
- GPG keyring issues

### 📦 Staged Upgrade Strategy

1. **Minimal Upgrade** - Only upgrade existing packages
2. **Safe Upgrade** - Upgrade without removing packages
3. **Full Upgrade** - Complete distribution upgrade

### 💾 Backup and Recovery

Automatic backup before upgrade:
- APT source configurations
- Critical system configuration files
- Installed package lists
- Network and SSH configurations

## 📊 System Requirements

### Minimum Requirements
- Debian 8 or higher
- 2GB available disk space
- 512MB available memory
- Stable internet connection

### Recommended Configuration
- 4GB available disk space
- 1GB+ available memory
- User account with sudo privileges

## ⚠️ Important Notes

> **Critical Reminder**: System upgrade is a critical operation. Please prepare the following before upgrading:

### 🚨 Version-Specific Warnings

**For Debian 12 Users:**
- ✅ You're on the **current stable version** - recommended to stay
- ⚠️ Upgrading to Debian 13 means moving to **testing branch** (unstable)
- 🛡️ Use `--stable-only` flag to avoid accidental testing upgrades
- 💡 The script will warn and require explicit 'YES' confirmation for testing upgrades

**For All Users:**

### Pre-upgrade Preparation
1. 📸 **Create system snapshot** (if on VPS)
2. 💾 **Backup important data**
3. 📝 **Record current system configuration**
4. 🔑 **Ensure console access is available**
5. 🧪 **Test the upgrade process in a development environment first**

### Special Notes for VPS Users
- Ensure your VPS provider supports console access
- SSH connection may be temporarily interrupted during upgrade
- Recommend performing upgrades during maintenance windows
- Prepare VPS restart and recovery plans
- Have emergency contact information for your VPS provider ready

### Version Upgrade Behavior
- **Stable → Stable**: Simple confirmation required
- **Stable → Testing**: Explicit 'YES' confirmation required with detailed warnings
- **`--stable-only` mode**: Will not offer testing version upgrades
- **`--force` mode**: Skips all confirmations (use with extreme caution)

## 🐛 Troubleshooting

### Common Issues

<details>
<summary>❓ APT lock errors during upgrade</summary>

```bash
# Run fix mode
./debian_upgrade.sh --fix-only
```
</details>

<details>
<summary>❓ Package dependency conflicts</summary>

The script automatically attempts to fix dependency issues. If problems persist:

```bash
# Manually fix dependencies
sudo apt --fix-broken install
sudo dpkg --configure -a
```
</details>

<details>
<summary>❓ Network connection issues</summary>

The script supports multiple mirror sources and retry mechanisms. If issues persist:

1. Check network connection
2. Manually configure DNS: `echo "nameserver 8.8.8.8" >> /etc/resolv.conf`
3. Use `--debug` mode for detailed information
</details>

<details>
<summary>❓ Cannot connect to VPS after upgrade</summary>

1. Login using VPS console
2. Check network configuration: `ip addr show`
3. Restart network service: `systemctl restart networking`
4. Restore backup configuration
</details>

### Getting Help

When reporting issues, please provide:

1. Current Debian version: `cat /etc/os-release`
2. Error logs: Run with `--debug` parameter
3. System environment: Physical/VPS type
4. Network environment: Proxy/firewall usage

## 🤝 Contributing

Contributions are welcome! Please feel free to submit Issues and Pull Requests.

### How to Contribute

1. Fork this repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit changes: `git commit -m 'Add amazing feature'`
4. Push to branch: `git push origin feature/amazing-feature`
5. Submit a Pull Request

### Development Guidelines

- Follow Bash scripting best practices
- Add appropriate error handling
- Write clear log messages
- Update relevant documentation

## 📚 Documentation

- [Installation Guide](docs/installation.md)
- [Usage Instructions](docs/usage.md)
- [Troubleshooting Guide](docs/troubleshooting.md)
- [FAQ](docs/faq.md)
- [API Reference](docs/api.md)

## 📈 Project Statistics

![GitHub stars](https://img.shields.io/github/stars/everett7623/debian-auto-upgrade.svg?style=social)
![GitHub forks](https://img.shields.io/github/forks/everett7623/debian-auto-upgrade.svg?style=social)
![GitHub issues](https://img.shields.io/github/issues/everett7623/debian-auto-upgrade.svg)
![GitHub last commit](https://img.shields.io/github/last-commit/everett7623/debian-auto-upgrade.svg)

## 📄 License

This project is licensed under the [MIT License](LICENSE).

## 🙏 Acknowledgments

- Debian Project and maintainers
- Mirror source providers
- Community feedback and suggestions

## 📞 Contact

- 📧 Email: everett7623@gmail.com
- 🐛 Bug Reports: [GitHub Issues](https://github.com/everett7623/debian-auto-upgrade/issues)
- 💬 Discussions: [GitHub Discussions](https://github.com/everett7623/debian-auto-upgrade/discussions)

---

<div align="center">

**⭐ If this project helps you, please give it a star! ⭐**

**🛡️ Remember: Debian 12 (Bookworm) is stable - consider staying on it for production systems**

[⬆️ Back to Top](#debian-auto-upgrade)

</div>

## 📈 Version History

- **v2.1** - Smart version control, testing version warnings, input fixes
- **v2.0** - Complete rewrite with VPS optimization and advanced features  
- **v1.0** - Basic upgrade functionality

See [CHANGELOG.md](CHANGELOG.md) for detailed version history.
