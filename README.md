# 🚀 Debian Auto Upgrade Tool

> Intelligent Debian system upgrade tool with VPS optimization, automatic error fixing, and progressive upgrade strategy

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![GitHub release](https://img.shields.io/github/release/everett7623/debian-auto-upgrade.svg)](https://github.com/everett7623/debian-auto-upgrade/releases)
[![Debian](https://img.shields.io/badge/Debian-8%2B-red.svg)](https://www.debian.org/)
[![Bash](https://img.shields.io/badge/Language-Bash-green.svg)](https://www.gnu.org/software/bash/)

A powerful automated upgrade script designed specifically for Debian systems, capable of safely upgrading systems from older versions to the latest release step by step. Specially optimized for VPS environments with robust error recovery and fault tolerance capabilities.

## ✨ Features

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

## 🎯 Supported Upgrade Paths

| Source Version | Target Version | Status | Upgrade Safety | Notes |
|---|---|---|---|---|
| Debian 8 (Jessie) | Debian 9 (Stretch) | ✅ Supported | 🔒 Safe | Legacy upgrade |
| Debian 9 (Stretch) | Debian 10 (Buster) | ✅ Supported | 🔒 Safe | Legacy upgrade |
| Debian 10 (Buster) | Debian 11 (Bullseye) | ✅ Supported | 🔒 Safe | Stable upgrade |
| Debian 11 (Bullseye) | Debian 12 (Bookworm) | ✅ Supported | 🔒 Safe | Current stable |
| Debian 12 (Bookworm) | Debian 13 (Trixie) | ⚠️ Testing | 🧪 Caution | Testing version - requires explicit confirmation |

> **Recommendation:** For production systems, stay on Debian 12 (Bookworm) as it's the current stable release.

## 🚀 Quick Start

### One-Line Installation

```bash
wget -O debian_upgrade.sh https://raw.githubusercontent.com/everett7623/debian-auto-upgrade/main/debian_upgrade.sh && chmod +x debian_upgrade.sh && ./debian_upgrade.sh
```

### Basic Usage

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

## 📖 Command Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Display help information |
| `-v, --version` | Show current Debian version |
| `-c, --check` | Check available upgrades |
| `-d, --debug` | Enable debug mode for troubleshooting |
| `--fix-only` | Fix system issues only (no upgrade) |
| `--force` | Force upgrade (skip confirmation prompts) |
| `--stable-only` | Only upgrade to stable versions (recommended) |
| `--allow-testing` | Allow upgrades to testing versions |

## 💡 Usage Examples

### For Production Servers (Recommended):

```bash
# Check what's available without upgrading
./debian_upgrade.sh --stable-only --check

# Upgrade only to stable versions
./debian_upgrade.sh --stable-only
```

### For Development/Testing:

```bash
# Allow testing versions (requires explicit confirmation)
./debian_upgrade.sh --allow-testing

# Force upgrade for automation (be careful!)
./debian_upgrade.sh --force

# Combine options
./debian_upgrade.sh --stable-only --debug
```

## 🌍 Smart Mirror Selection

The script automatically selects optimal software source mirrors based on your geographic location:

- 🇨🇳 **China** - Tsinghua University, USTC, NetEase mirrors
- 🇺🇸 **United States** - US official mirrors
- 🇬🇧 **United Kingdom** - UK official mirrors
- 🇩🇪 **Germany** - German official mirrors
- 🇯🇵 **Japan** - Japanese official mirrors

## 🛠️ VPS Environment Detection

Automatically detects and fixes common VPS issues:

- **Virtualization:** OpenVZ, KVM, Xen, VMware environments
- **Cloud Providers:** AWS EC2, Alibaba Cloud, Tencent Cloud servers
- **Common Issues:** DNS configuration, timezone settings, GPG keyring problems

## 📦 Upgrade Strategy

### Progressive Upgrade Phases:
1. **Minimal Upgrade** - Only upgrade existing packages
2. **Safe Upgrade** - Upgrade without removing packages
3. **Full Upgrade** - Complete distribution upgrade

### Automatic Backup:
- APT source configurations
- Critical system configuration files
- Installed package lists
- Network and SSH configurations

## 💻 System Requirements

### Minimum Requirements:
- Debian 8 or higher
- 2GB available disk space
- 512MB available memory
- Stable internet connection

### Recommended for Production:
- 4GB available disk space
- 1GB+ available memory
- User account with sudo privileges

## ⚠️ Important Safety Notes

### Critical Reminder:
System upgrade is a critical operation. Please prepare the following before upgrading:

### For Debian 12 Users:
- ✅ You're on the current stable version - **recommended to stay**
- ⚠️ Upgrading to Debian 13 means moving to testing branch (unstable)
- 🛡️ Use `--stable-only` flag to avoid accidental testing upgrades
- 💡 The script will warn and require explicit 'YES' confirmation for testing upgrades

### For All Users:
- 📸 Create system snapshot (if on VPS)
- 💾 Backup important data
- 📝 Record current system configuration
- 🔑 Ensure console access is available
- 🧪 Test the upgrade process in a development environment first

### VPS-Specific Considerations:
- Ensure your VPS provider supports console access
- SSH connection may be temporarily interrupted during upgrade
- Recommend performing upgrades during maintenance windows
- Prepare VPS restart and recovery plans
- Have emergency contact information for your VPS provider ready

## 🔒 Security & Confirmation

### Confirmation Levels:
- **Stable → Stable:** Simple confirmation required
- **Stable → Testing:** Explicit 'YES' confirmation required with detailed warnings
- **`--stable-only` mode:** Will not offer testing version upgrades
- **`--force` mode:** Skips all confirmations (use with extreme caution)

## 🐛 Troubleshooting

### Common Issues:

#### ❓ APT lock errors during upgrade
```bash
# Run fix mode
./debian_upgrade.sh --fix-only
```

#### ❓ Package dependency conflicts
The script automatically attempts to fix dependency issues. If problems persist:
```bash
# Manually fix dependencies
sudo apt --fix-broken install
sudo dpkg --configure -a
```

#### ❓ Network connection issues
The script supports multiple mirror sources and retry mechanisms. If issues persist:
- Check network connection
- Manually configure DNS: `echo "nameserver 8.8.8.8" >> /etc/resolv.conf`
- Use `--debug` mode for detailed information

#### ❓ Cannot connect to VPS after upgrade
- Login using VPS console
- Check network configuration: `ip addr show`
- Restart network service: `systemctl restart networking`
- Restore backup configuration

## 📄 Reporting Issues

When reporting issues, please provide:
- Current Debian version: `cat /etc/os-release`
- Error logs: Run with `--debug` parameter
- System environment: Physical/VPS type
- Network environment: Proxy/firewall usage

## 🤝 Contributing

Contributions are welcome! Please feel free to submit Issues and Pull Requests.

### Development Process:
1. Fork this repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit changes: `git commit -m 'Add amazing feature'`
4. Push to branch: `git push origin feature/amazing-feature`
5. Submit a Pull Request

### Guidelines:
- Follow Bash scripting best practices
- Add appropriate error handling
- Write clear log messages
- Update relevant documentation

## 📝 License

This project is licensed under the [MIT License](LICENSE).

## 🙏 Acknowledgments

- Debian Project and maintainers
- Mirror source providers
- Community feedback and suggestions

## 📞 Support

- 📧 Email: [everett7623@gmail.com](mailto:everett7623@gmail.com)
- 🐛 Bug Reports: [GitHub Issues](https://github.com/everett7623/debian-auto-upgrade/issues)
- 💬 Discussions: [GitHub Discussions](https://github.com/everett7623/debian-auto-upgrade/discussions)

---

⭐ **If this project helps you, please give it a star!** ⭐

🛡️ **Remember:** Debian 12 (Bookworm) is stable - consider staying on it for production systems

## 📚 Version History

- **v2.2** - Fixed syntax errors, improved main function handling
- **v2.1** - Smart version control, testing version warnings, input fixes
- **v2.0** - Complete rewrite with VPS optimization and advanced features
- **v1.0** - Basic upgrade functionality

See [CHANGELOG.md](CHANGELOG.md) for detailed version history.
