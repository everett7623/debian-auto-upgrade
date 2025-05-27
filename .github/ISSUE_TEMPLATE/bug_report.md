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
        - VPS (
