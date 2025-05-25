# Changelog

All notable changes to the Debian Auto Upgrade project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Web interface for remote management
- Configuration file support
- Multi-language localization
- Batch upgrade capabilities for multiple servers

## [2.1.0] - 2025-05-26

### 🎯 Major Features Added
- **Smart Version Control** - Prevents accidental upgrades to unstable versions
- **Enhanced User Confirmation** - Explicit confirmation required for testing/unstable versions
- **Stable-Only Mode** - New `--stable-only` flag to limit upgrades to stable releases only
- **Testing Version Warnings** - Comprehensive risk assessment and warnings for non-stable versions

### 🔧 Critical Fixes
- **Fixed Input Handling** - Resolved issue where script would auto-exit without waiting for user input
- **Terminal Input Redirection** - All user input now properly redirected from `/dev/tty`
- **Syntax Error Correction** - Fixed bash syntax error in `perform_staged_upgrade()` function
- **Confirmation Logic** - Improved user confirmation flow for better reliability

### ✨ Enhancements
- **New Command Line Options**:
  - `--stable-only` - Only upgrade to stable versions
  - `--allow-testing` - Explicitly allow upgrades to testing versions
- **Improved Risk Communication**:
  - Color-coded warnings for different version types
  - Detailed risk explanations for testing versions
  - Clear recommendations based on environment type
- **Enhanced User Experience**:
  - Better formatting of version information
  - Clearer status messages and progress indicators
  - Improved help documentation with usage examples

### 🛡️ Security Improvements
- **Version Validation** - Enhanced validation of target versions before upgrade
- **Safer Defaults** - Default behavior now more conservative for production environments
- **Input Sanitization** - Improved handling of user input to prevent unexpected behavior

### 📚 Documentation Updates
- **Updated README** - Comprehensive documentation of new features and safety guidelines
- **Usage Examples** - Added examples for different use cases (production, development, automation)
- **Best Practices** - Detailed recommendations for different environments

### 🔄 Behavioral Changes
- **Breaking**: Default behavior now requires explicit confirmation for testing versions
- **Breaking**: Debian 12 users will see warnings when upgrading to Debian 13 (testing)
- **Improved**: Better handling of VPS environment detection and fixes

## [2.0.0] - 2025-05-25

### 🚀 Complete Rewrite
- **New Architecture** - Rebuilt from ground up with modern bash practices
- **VPS Optimization** - Comprehensive VPS environment detection and fixes
- **Smart Mirror Selection** - Geographic-based mirror selection for optimal performance
- **Advanced Error Handling** - Robust error recovery and fault tolerance

### 🔧 Advanced Features Added
- **Staged Upgrade Strategy** - Progressive upgrade approach (minimal → safe → full)
- **Comprehensive Backup System** - Automatic backup of critical configurations before upgrade
- **Enhanced System Verification** - Pre and post-upgrade system health checks
- **Intelligent Retry Logic** - Network timeout handling with exponential backoff
- **Multiple Operation Modes** - Check, fix-only, debug, and force modes

### 🌍 Geographic Optimization
- **China Mirror Support** - Optimized mirrors for Chinese users (Tsinghua, USTC, NetEase)
- **Regional Mirror Selection** - Automatic selection based on geographic location
- **Fallback Mechanisms** - Graceful fallback to official mirrors when needed

### 🔍 System Detection & Repair
- **VPS Environment Detection**:
  - OpenVZ, KVM, Xen, VMware support
  - AWS EC2, DigitalOcean, Vultr, Linode compatibility
  - Docker and LXC container support
- **Automatic Issue Resolution**:
  - GPG key management and updates
  - DNS configuration fixes
  - Locale and timezone setup
  - APT lock file cleanup

### 📦 Package Management Improvements
- **Dependency Resolution** - Advanced handling of package dependencies
- **Conflict Detection** - Automatic detection and resolution of package conflicts
- **Essential Package Protection** - Special handling for critical system packages
- **Source Management** - Intelligent software source configuration and cleanup

### 🛡️ Safety & Security
- **Pre-upgrade Validation** - Comprehensive system checks before upgrade
- **Rollback Preparation** - Complete backup strategy for easy recovery
- **Service Monitoring** - Critical service status tracking during upgrade
- **Network Validation** - Connectivity verification throughout process

### 📊 Logging & Monitoring
- **Colorized Output** - Enhanced readability with color-coded messages
- **Timestamp Logging** - All operations logged with precise timestamps
- **Debug Mode** - Detailed debugging information for troubleshooting
- **Progress Tracking** - Clear indication of upgrade progress and current phase

## [1.0.0] - 2025-05-25

### 🎉 Initial Release
- **Basic Upgrade Functionality** - Core Debian version upgrade capabilities
- **Version Detection** - Automatic current version detection
- **Simple Software Source Management** - Basic repository configuration
- **Elementary Error Handling** - Basic error detection and handling

### 📋 Supported Features
- Support for Debian 8-12 upgrades
- Automatic software source updates
- Basic backup functionality
- Simple logging system
- Command-line interface with basic options

### 🎯 Supported Versions
- Debian 8 (Jessie) to Debian 9 (Stretch)
- Debian 9 (Stretch) to Debian 10 (Buster)
- Debian 10 (Buster) to Debian 11 (Bullseye)
- Debian 11 (Bullseye) to Debian 12 (Bookworm)

---

## Version Numbering Scheme

This project uses [Semantic Versioning](https://semver.org/):

- **MAJOR** version when making incompatible changes or major rewrites
- **MINOR** version when adding functionality in a backwards compatible manner
- **PATCH** version when making backwards compatible bug fixes

## Release Process

1. **Development** - Feature development and testing
2. **Testing** - Comprehensive testing across different Debian versions and VPS providers
3. **Documentation** - Update README, CHANGELOG, and inline documentation
4. **Release** - Create GitHub release with detailed release notes
5. **Tagging** - Tag release with version number following semver

## Migration Guide

### Upgrading from v1.x to v2.0+
- **Script Compatibility**: v2.0+ is a complete rewrite but maintains command-line compatibility
- **New Features**: Many new options available, see `--help` for details
- **Backup Location**: Configuration backup location changed to `/var/backups/debian-upgrade-*`
- **Behavior Changes**: More conservative defaults and better error handling
- **No Manual Migration**: Previous configurations are automatically migrated

### Upgrading from v2.0 to v2.1+
- **New Options**: `--stable-only` and `--allow-testing` options available
- **Behavior Change**: More explicit confirmation required for testing versions
- **Backward Compatibility**: All v2.0 options remain functional
- **Recommended**: Update scripts to use `--stable-only` for production environments

## Support Policy

- **Current Version** (v2.1.x): Full support with regular updates
- **Previous Major** (v2.0.x): Security fixes and critical bug fixes
- **Legacy Versions** (v1.x): No longer supported, upgrade recommended

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on:
- Reporting bugs
- Suggesting features
- Code contributions
- Testing procedures

## Acknowledgements

Special thanks to:
- Debian Project maintainers
- VPS provider communities
- Beta testers and early adopters
- Contributors who provided feedback and bug reports
