# Contributing to Debian Auto Upgrade

Thank you for your interest in contributing to the Debian Auto Upgrade project! We welcome contributions from the community and are pleased to have you participate.

## 🤝 Ways to Contribute

### 1. Reporting Bugs
- Use our [bug report template](.github/ISSUE_TEMPLATE/bug_report.md)
- Include system information (Debian version, VPS type, etc.)
- Provide detailed steps to reproduce the issue
- Include log output with `--debug` flag

### 2. Suggesting Features
- Use our [feature request template](.github/ISSUE_TEMPLATE/feature_request.md)
- Explain the use case and benefits
- Consider implementation complexity
- Discuss potential impact on existing functionality

### 3. Improving Documentation
- Fix typos and grammar errors
- Add missing information
- Improve clarity and examples
- Translate documentation to other languages

### 4. Code Contributions
- Fix bugs and implement features
- Improve error handling
- Add support for new Debian versions
- Optimize performance

## 🚀 Getting Started

### Prerequisites
- Debian system (8+ recommended)
- Basic knowledge of Bash scripting
- Familiarity with APT package management
- Git for version control

### Setting Up Development Environment

1. **Fork the repository**
   ```bash
   # Click "Fork" on GitHub, then clone your fork
   git clone https://github.com/YOUR_USERNAME/debian-auto-upgrade.git
   cd debian-auto-upgrade
   ```

2. **Set up upstream remote**
   ```bash
   git remote add upstream https://github.com/everett7623/debian-auto-upgrade.git
   ```

3. **Create a development branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

4. **Install development dependencies**
   ```bash
   # For testing and linting
   sudo apt update
   sudo apt install shellcheck bats
   ```

## 💻 Development Guidelines

### Code Style

1. **Shell Script Standards**
   - Use `#!/bin/bash` shebang
   - Follow Google Shell Style Guide
   - Use 4 spaces for indentation
   - Keep lines under 100 characters

2. **Variable Naming**
   - Use lowercase with underscores: `current_version`
   - Constants in uppercase: `MAX_RETRIES`
   - Local variables: `local var_name`

3. **Function Guidelines**
   ```bash
   # Good function structure
   function_name() {
       local param1="$1"
       local param2="$2"
       
       # Validation
       [[ -z "$param1" ]] && {
           log_error "Parameter required"
           return 1
       }
       
       # Main logic
       log_info "Performing action..."
       
       # Return appropriate exit code
       return 0
   }
   ```

4. **Error Handling**
   ```bash
   # Always handle errors
   if ! command_that_might_fail; then
       log_error "Command failed"
       return 1
   fi
   
   # Use proper exit codes
   exit 0  # Success
   exit 1  # General error
   exit 2  # Misuse of shell builtins
   ```

### Logging Standards

```bash
# Use consistent logging functions
log_info "Informational message"
log_success "Success message"
log_warning "Warning message"
log_error "Error message"
log_debug "Debug message (only in debug mode)"
```

### Testing Requirements

1. **Unit Tests**
   ```bash
   # Run existing tests
   ./tests/test_basic.sh
   
   # Add tests for new functions
   # Use BATS framework for structured testing
   ```

2. **Integration Tests**
   ```bash
   # Test on clean Debian installations
   # Verify different upgrade paths
   # Test VPS-specific scenarios
   ```

3. **Manual Testing Checklist**
   - [ ] Script works on different Debian versions
   - [ ] Error conditions are handled gracefully
   - [ ] Backup and restore functionality works
   - [ ] VPS-specific fixes are effective
   - [ ] Log output is clear and helpful

## 📝 Commit Guidelines

### Commit Message Format
```
type(scope): brief description

Detailed explanation of changes (if needed)

Closes #issue_number
```

### Types
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

### Examples
```bash
feat(upgrade): add support for Debian 13 (Trixie)
fix(vps): resolve OpenVZ container detection issue
docs(readme): update installation instructions
test(core): add unit tests for version detection
```

## 🔍 Code Review Process

### Before Submitting PR

1. **Self Review**
   - [ ] Code follows style guidelines
   - [ ] All tests pass
   - [ ] Documentation is updated
   - [ ] Commit messages are clear

2. **Testing**
   - [ ] Test on multiple Debian versions
   - [ ] Verify VPS compatibility
   - [ ] Check error handling
   - [ ] Validate log output

3. **Documentation**
   - [ ] Update README if needed
   - [ ] Add/update function documentation
   - [ ] Update CHANGELOG.md
   - [ ] Add examples if applicable

### Pull Request Template

When creating a PR, please:

1. Use our [PR template](.github/PULL_REQUEST_TEMPLATE.md)
2. Reference related issues
3. Provide testing information
4. Include screenshots/logs if relevant

### Review Criteria

PRs will be reviewed for:
- **Functionality**: Does it work as intended?
- **Compatibility**: Works across supported Debian versions?
- **Error Handling**: Graceful failure and recovery?
- **Code Quality**: Readable, maintainable, follows guidelines?
- **Testing**: Adequate test coverage?
- **Documentation**: Clear and complete?

## 🛠️ Development Tools

### Recommended Tools

1. **ShellCheck** - Static analysis
   ```bash
   shellcheck debian_upgrade.sh
   ```

2. **BATS** - Bash testing framework
   ```bash
   bats tests/test_basic.bats
   ```

3. **Git Hooks** - Pre-commit validation
   ```bash
   # Install pre-commit hooks
   cp scripts/pre-commit .git/hooks/
   chmod +x .git/hooks/pre-commit
   ```

### Debugging Tips

1. **Enable Debug Mode**
   ```bash
   ./debian_upgrade.sh --debug
   ```

2. **Test in Containers**
   ```bash
   # Use Docker for safe testing
   docker run -it debian:11 bash
   ```

3. **Validate with Different Scenarios**
   - Clean installations
   - Systems with issues
   - Various VPS providers
   - Different network conditions

## 🐛 Bug Report Guidelines

### Information to Include

1. **System Information**
   ```bash
   cat /etc/os-release
   cat /etc/debian_version
   uname -a
   ```

2. **Script Output**
   ```bash
   # Run with debug mode
   ./debian_upgrade.sh --debug 2>&1 | tee debug.log
   ```

3. **Environment Details**
   - VPS provider (if applicable)
   - Network configuration
   - Any customizations made

### Severity Levels

- **Critical**: System becomes unusable
- **High**: Major functionality broken
- **Medium**: Feature partially working
- **Low**: Minor issues or enhancements

## 📚 Documentation Standards

### Code Documentation

```bash
# Function documentation template
#
# Description: Brief description of what the function does
# Parameters:
#   $1 - First parameter description
#   $2 - Second parameter description
# Returns:
#   0 - Success
#   1 - Error condition
# Globals:
#   GLOBAL_VAR - Global variable used
#
function_name() {
    # Implementation
}
```

### README Updates

When adding features, update:
- Feature list
- Usage examples
- Command-line options
- System requirements
- Supported versions

## 🎯 Priority Areas

We especially welcome contributions in these areas:

1. **VPS Compatibility**
   - Support for new VPS providers
   - Container-specific optimizations
   - Cloud platform integrations

2. **Error Recovery**
   - Better error detection
   - Automatic fix strategies
   - Recovery procedures

3. **Performance**
   - Faster upgrade processes
   - Reduced download sizes
   - Parallel operations

4. **Internationalization**
   - Multi-language support
   - Regional mirror optimization
   - Locale-specific fixes

## 🏆 Recognition

Contributors will be:
- Listed in the project README
- Mentioned in release notes
- Added to the contributors section

## 📞 Getting Help

Need help contributing?

- 💬 [GitHub Discussions](https://github.com/everett7623/debian-auto-upgrade/discussions)
- 📧 Email: everett7623@gmail.com
- 🐛 [Issues](https://github.com/everett7623/debian-auto-upgrade/issues)

## 📄 License

By contributing to this project, you agree that your contributions will be licensed under the same [MIT License](LICENSE) that covers the project.
