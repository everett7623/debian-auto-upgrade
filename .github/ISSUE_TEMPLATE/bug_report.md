name: Bug Report
description: File a bug report to help us improve
title: "[Bug]: "
labels: ["bug", "triage"]
projects: ["everett7623/1"]
assignees:
  - everett7623
body:
  - type: markdown
    attributes:
      value: |
        Thanks for taking the time to fill out this bug report! 🐛
        
        Please provide as much detail as possible to help us understand and reproduce the issue.

  - type: checkboxes
    id: checks
    attributes:
      label: Pre-flight Checklist
      description: Please confirm you have completed these steps
      options:
        - label: I have searched existing issues to ensure this bug hasn't been reported before
          required: true
        - label: I am using the latest version of the script
          required: true
        - label: I have tested the script syntax with `bash -n debian_upgrade.sh`
          required: true

  - type: textarea
    id: bug-description
    attributes:
      label: Bug Description
      description: A clear and concise description of what the bug is
      placeholder: Describe what happened...
    validations:
      required: true

  - type: textarea
    id: reproduce-steps
    attributes:
      label: Steps to Reproduce
      description: Detailed steps to reproduce the behavior
      placeholder: |
        1. Run the command '...'
        2. Select option '....'
        3. See error at step '....'
        4. Error message appears
    validations:
      required: true

  - type: textarea
    id: expected-behavior
    attributes:
      label: Expected Behavior
      description: A clear description of what you expected to happen
      placeholder: What should have happened instead?
    validations:
      required: true

  - type: dropdown
    id: debian-version
    attributes:
      label: Debian Version
      description: What version of Debian are you running?
      options:
        - Debian 8 (Jessie)
        - Debian 9 (Stretch)
        - Debian 10 (Buster)
        - Debian 11 (Bullseye)
        - Debian 12 (Bookworm)
        - Debian 13 (Trixie)
        - Other (please specify in additional context)
    validations:
      required: true

  - type: dropdown
    id: environment
    attributes:
      label: Environment Type
      description: What type of environment are you running on?
      options:
        - Physical Server
        - VPS (KVM)
        - VPS (OpenVZ)
        - VPS (Xen)
        - AWS EC2
        - Google Cloud
        - Azure
        - DigitalOcean
        - Linode
        - Vultr
        - Docker Container
        - LXC Container
        - VMware
        - VirtualBox
        - Other (please specify)
    validations:
      required: true

  - type: input
    id: script-version
    attributes:
      label: Script Version
      description: What version of the script are you using?
      placeholder: "e.g., 2.2, or output from ./debian_upgrade.sh --version"
    validations:
      required: true

  - type: dropdown
    id: command-used
    attributes:
      label: Command Used
      description: Which command triggered the bug?
      options:
        - "./debian_upgrade.sh"
        - "./debian_upgrade.sh --check"
        - "./debian_upgrade.sh --stable-only"
        - "./debian_upgrade.sh --allow-testing"
        - "./debian_upgrade.sh --fix-only"
        - "./debian_upgrade.sh --force"
        - "./debian_upgrade.sh --debug"
        - "Other combination (specify below)"
    validations:
      required: true

  - type: textarea
    id: debug-output
    attributes:
      label: Debug Output
      description: |
        Please run the script with --debug flag and paste the relevant output here.
        **Important**: Remove any sensitive information like IP addresses, usernames, etc.
      placeholder: |
        $ ./debian_upgrade.sh --debug --check
        [DEBUG] 10:30:15 - Starting debug mode...
        [ERROR] 10:30:16 - Something went wrong...
      render: shell

  - type: textarea
    id: error-logs
    attributes:
      label: Error Messages
      description: Any specific error messages you encountered
      placeholder: Paste exact error messages here...
      render: text

  - type: textarea
    id: system-info
    attributes:
      label: System Information
      description: |
        Please provide the output of these commands:
        ```bash
        cat /etc/os-release
        uname -a
        df -h
        free -h
        ```
      placeholder: Paste system information here...
      render: shell

  - type: textarea
    id: network-config
    attributes:
      label: Network Configuration
      description: |
        If the issue is network-related, please provide:
        - Are you behind a proxy or firewall?
        - Any custom DNS configuration?
        - Geographic location (country) for mirror selection
      placeholder: Describe your network setup...

  - type: textarea
    id: additional-context
    attributes:
      label: Additional Context
      description: |
        Add any other context about the problem here:
        - Screenshots (if applicable)
        - Previous successful upgrades
        - Recent system changes
        - Custom configurations
      placeholder: Any additional information that might help...

  - type: checkboxes
    id: attempted-solutions
    attributes:
      label: Attempted Solutions
      description: What have you tried to fix this issue?
      options:
        - label: Ran `./debian_upgrade.sh --fix-only`
        - label: Manually fixed APT issues with `sudo apt --fix-broken install`
        - label: Cleared APT cache with `sudo apt clean`
        - label: Checked disk space and memory
        - label: Verified network connectivity
        - label: Tried different mirror sources
        - label: Ran script with --debug for more information
        - label: Checked system logs in /var/log/

  - type: checkboxes
    id: impact
    attributes:
      label: Impact Assessment
      description: How does this bug affect you?
      options:
        - label: Prevents script from running at all
        - label: Causes upgrade to fail partway through
        - label: Results in incorrect behavior but script completes
        - label: Minor inconvenience but workaround exists
        - label: Security-related issue
        - label: Data loss or system corruption

  - type: dropdown
    id: urgency
    attributes:
      label: Urgency Level
      description: How urgent is this fix for you?
      options:
        - Low - Can wait for next release
        - Medium - Would like fix in upcoming release
        - High - Blocking critical operations
        - Critical - Security issue or data loss
    validations:
      required: true

  - type: markdown
    attributes:
      value: |
        ---
        
        ### 📝 Additional Notes
        
        - **For security issues**: Please email [everett7623@gmail.com](mailto:everett7623@gmail.com) instead of creating a public issue
        - **For questions**: Consider using [GitHub Discussions](https://github.com/everett7623/debian-auto-upgrade/discussions) instead
        - **Response time**: We typically respond to bug reports within 24-48 hours
        
        Thank you for helping improve the Debian Auto Upgrade Tool! 🚀
