# Contributing to Debian Auto Upgrade Tool

We love your input! We want to make contributing to this project as easy and transparent as possible, whether it's:

- Reporting a bug
- Discussing the current state of the code
- Submitting a fix
- Proposing new features
- Becoming a maintainer

## 🚀 Quick Start for Contributors

1. **Fork the Repository**
   ```bash
   # Fork via GitHub UI, then clone
   git clone https://github.com/YOUR_USERNAME/debian-auto-upgrade.git
   cd debian-auto-upgrade
   ```

2. **Create a Feature Branch**
   ```bash
   git checkout -b feature/amazing-feature
   # or
   git checkout -b fix/important-bug
   ```

3. **Make Your Changes**
   - Edit the code
   - Test your changes
   - Update documentation if needed

4. **Test Thoroughly**
   ```bash
   # Check syntax
   bash -n debian_upgrade.sh
   
   # Test basic functionality
   ./debian_upgrade.sh --check
   ./debian_upgrade.sh --help
   
   # Test in different environments if possible
   ```

5. **Commit and Push**
   ```bash
   git add .
   git commit -m "Add amazing feature"
   git push origin feature/amazing-feature
   ```

6. **Submit a Pull Request**
   - Go to GitHub and create a pull request
   - Describe your changes clearly
   - Reference any related issues

## 📋 Development Guidelines

### Code Style

#### Bash Scripting Best Practices
- Use `#!/bin/bash` shebang
- Enable strict mode with `set -e`
- Use meaningful variable names
- Quote variables properly: `"$variable"`
- Use functions for reusable code
- Add comments for complex logic

#### Example Code Style:
```bash
# Good
local version_id=""
if [[ -f /etc/os-release ]]; then
    version_id=$(grep "^VERSION_ID=" /etc/os-release | cut -d'"' -f2)
    log_debug "Found version: '$version_id'"
fi

# Avoid
ver=$(cat /etc/os-release | grep VERSION_ID | sed 's/.*="//' | sed 's/"//')
```

### Error Handling

#### Always Include Error Handling:
```bash
# Good
if ! command_that_might_fail; then
    log_error "Command failed"
    return 1
fi

# Better
command_that_might_fail || {
    log_error "Command failed with exit code $?"
    return 1
}
```

#### Use Proper Exit Codes:
- `0` - Success
- `1` - General error
- `2` - Misuse of shell command
- `3-125` - Custom error codes
- `126` - Command not executable
- `127` - Command not found

### Logging Standards

#### Use Appropriate Log Levels:
```bash
log_debug "Detailed debugging information"
log_info "General information"
log_warning "Warning - something might be wrong"
log_error "Error - something went wrong"
log_success "Success - operation completed"
```

#### Log Message Format:
- Start with capital letter
- Be descriptive but concise
- Include relevant context
- Use present tense

### Testing Requirements

#### Before Submitting:
1. **Syntax Check**: `bash -n debian_upgrade.sh`
2. **Basic Functionality**: Test all major functions
3. **Error Scenarios**: Test error handling
4. **Different Environments**: Test on different Debian versions if possible

#### Test Coverage Areas:
- Version detection
- Mirror selection
- Upgrade simulation (`--check` mode)
- Error recovery
- User input handling
- VPS environment detection

## 🐛 Bug Reports

### Before Creating an Issue:
1. **Search existing issues** - Your issue might already be reported
2. **Test with latest version** - Make sure you're using the current version
3. **Reproduce the bug** - Try to reproduce it consistently

### Bug Report Template:
```markdown
**Bug Description**
A clear and concise description of what the bug is.

**To Reproduce**
Steps to reproduce the behavior:
1. Go to '...'
2. Click on '....'
3. Scroll down to '....'
4. See error

**Expected Behavior**
A clear description of what you expected to happen.

**System Information**
- Debian Version: [e.g. Debian 11 Bullseye]
- Script Version: [e.g. 2.2]
- Environment: [e.g. VPS, Physical, Container]
- Virtualization: [e.g. KVM, OpenVZ, VMware]

**Debug Output**
If applicable, add the output from running with --debug flag:
```
./debian_upgrade.sh --debug --check
```

**Additional Context**
Add any other context about the problem here.
```

## ✨ Feature Requests

### Before Requesting:
1. Check if the feature already exists
2. Search existing feature requests
3. Consider if it fits the project's scope

### Feature Request Template:
```markdown
**Is your feature request related to a problem?**
A clear description of what the problem is. Ex. I'm always frustrated when [...]

**Describe the solution you'd like**
A clear description of what you want to happen.

**Describe alternatives you've considered**
A clear description of any alternative solutions you've considered.

**Use Cases**
Describe specific use cases where this feature would be helpful.

**Implementation Ideas**
If you have ideas about how this could be implemented, share them here.
```

## 🔍 Code Review Process

### What We Look For:
1. **Functionality** - Does it work as intended?
2. **Safety** - Is it safe for production systems?
3. **Code Quality** - Is it well-written and maintainable?
4. **Documentation** - Is it properly documented?
5. **Testing** - Has it been adequately tested?

### Review Checklist:
- [ ] Code follows project style guidelines
- [ ] Includes appropriate error handling
- [ ] Has proper logging and user feedback
- [ ] Maintains backward compatibility
- [ ] Includes documentation updates
- [ ] Has been tested in multiple scenarios

## 📚 Documentation

### What Needs Documentation:
- New features and options
- Changed behavior
- Configuration examples
- Troubleshooting steps
- API/function changes

### Documentation Style:
- Use clear, simple language
- Provide examples
- Include expected output
- Update relevant files (README, CHANGELOG, etc.)

## 🏷️ Versioning and Releases

### Version Numbering:
We follow [Semantic Versioning](https://semver.org/):
- **MAJOR.MINOR.PATCH** (e.g., 2.1.0)
- **MAJOR**: Breaking changes
- **MINOR**: New features (backward compatible)
- **PATCH**: Bug fixes (backward compatible)

### Changelog Updates:
When contributing, update `CHANGELOG.md` with:
- Brief description of changes
- Category: Added, Changed, Fixed, Removed, Security
- Reference to related issues/PRs

## 🤝 Community Guidelines

### Be Respectful:
- Use welcoming and inclusive language
- Be respectful of differing viewpoints
- Accept constructive criticism gracefully
- Focus on what's best for the community

### Communication Channels:
- **Issues**: Bug reports and feature requests
- **Discussions**: General questions and ideas
- **Pull Requests**: Code contributions
- **Email**: [everett7623@gmail.com](mailto:everett7623@gmail.com) for private matters

## 🛡️ Security

### Reporting Security Issues:
If you discover a security vulnerability, please:
1. **Don't create a public issue**
2. **Email us directly**: [everett7623@gmail.com](mailto:everett7623@gmail.com)
3. **Include detailed information** about the vulnerability
4. **Wait for confirmation** before disclosing publicly

### Security Considerations:
- This script runs with elevated privileges
- Changes affect system packages and configurations
- Always consider security implications of modifications
- Test security-related changes thoroughly

## 📝 License

By contributing, you agree that your contributions will be licensed under the same MIT License that covers the project. Feel free to contact us if that's a concern.

## ❓ Questions?

If you have questions about contributing, feel free to:
- Open a [Discussion](https://github.com/everett7623/debian-auto-upgrade/discussions)
- Email us at [everett7623@gmail.com](mailto:everett7623@gmail.com)
- Check our [FAQ section](README.md#troubleshooting)

## 🎉 Recognition

Contributors will be recognized in:
- README acknowledgments
- Release notes
- Contributor list (coming soon)

Thank you for helping make this project better! 🚀
