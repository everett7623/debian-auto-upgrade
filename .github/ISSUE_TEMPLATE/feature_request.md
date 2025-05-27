name: Feature Request
description: Suggest a new feature or improvement
title: "[Feature]: "
labels: ["enhancement", "triage"]
projects: ["everett7623/1"]
assignees:
  - everett7623
body:
  - type: markdown
    attributes:
      value: |
        Thanks for suggesting a new feature! 💡
        
        Please provide detailed information about your feature request to help us understand your needs.

  - type: checkboxes
    id: checks
    attributes:
      label: Pre-submission Checklist
      description: Please confirm you have completed these steps
      options:
        - label: I have searched existing issues and discussions to ensure this feature hasn't been requested before
          required: true
        - label: I have considered if this feature fits within the project's scope
          required: true
        - label: I have thought about potential implementation approaches
          required: true

  - type: dropdown
    id: feature-category
    attributes:
      label: Feature Category
      description: What type of feature is this?
      options:
        - User Interface / User Experience
        - System Detection / Compatibility
        - Upgrade Process / Strategy
        - Error Handling / Recovery
        - Logging / Reporting
        - Configuration / Options
        - Security / Safety
        - Performance / Optimization
        - Documentation / Help
        - Integration / API
        - Other (please specify)
    validations:
      required: true

  - type: textarea
    id: problem-statement
    attributes:
      label: Problem Statement
      description: Is your feature request related to a problem? Please describe.
      placeholder: |
        I'm always frustrated when...
        Currently it's difficult to...
        Users often struggle with...
    validations:
      required: true

  - type: textarea
    id: proposed-solution
    attributes:
      label: Proposed Solution
      description: Describe the solution you'd like to see implemented
      placeholder: |
        I would like the script to...
        The feature should work by...
        Users should be able to...
    validations:
      required: true

  - type: textarea
    id: use-cases
    attributes:
      label: Use Cases
      description: Describe specific scenarios where this feature would be helpful
      placeholder: |
        Scenario 1: When upgrading production servers...
        Scenario 2: For users in corporate environments...
        Scenario 3: When dealing with custom configurations...
    validations:
      required: true

  - type: textarea
    id: alternatives
    attributes:
      label: Alternatives Considered
      description: Describe any alternative solutions or features you've considered
      placeholder: |
        Alternative 1: Instead of X, we could do Y...
        Alternative 2: Another approach would be...
        Current workaround: Users currently have to...

  - type: dropdown
    id: target-users
    attributes:
      label: Target Users
      description: Who would primarily benefit from this feature?
      multiple: true
      options:
        - Beginners / New Linux users
        - System administrators
        - DevOps engineers
        - VPS users
        - Enterprise users
        - Power users / Advanced users
        - Automation / CI/CD systems
        - All users
    validations:
      required: true

  - type: dropdown
    id: priority-level
    attributes:
      label: Priority Level
      description: How important is this feature to you?
      options:
        - Nice to have
        - Would improve workflow
        - Important for my use case
        - Critical for adoption
        - Blocking current usage
    validations:
      required: true

  - type: textarea
    id: implementation-ideas
    attributes:
      label: Implementation Ideas
      description: |
        If you have ideas about how this could be implemented, share them here.
        Include technical details, command-line options, configuration formats, etc.
      placeholder: |
        This could be implemented by...
        New command-line option: --feature-name
        Configuration file changes...
        User interface changes...

  - type: textarea
    id: acceptance-criteria
    attributes:
      label: Acceptance Criteria
      description: What would need to be true for this feature to be considered complete?
      placeholder: |
        - [ ] Feature works on all supported Debian versions
        - [ ] Includes appropriate error handling
        - [ ] Has comprehensive documentation
        - [ ] Includes tests/validation
        - [ ] Maintains backward compatibility

  - type: dropdown
    id: complexity-estimate
    attributes:
      label: Estimated Complexity
      description: How complex do you think this feature would be to implement?
      options:
        - Simple - Minor addition or modification
        - Moderate - Requires some new functionality
        - Complex - Significant changes or new subsystem
        - Major - Fundamental changes to architecture
        - Unknown - Not sure about implementation complexity

  - type: checkboxes
    id: compatibility-concerns
    attributes:
      label: Compatibility Considerations
      description: Please check any that apply to your feature request
      options:
        - label: Should work on all supported Debian versions (8-13)
        - label: Should work in VPS environments
        - label: Should work with different virtualization platforms
        - label: Should maintain backward compatibility
        - label: Should work with existing command-line options
        - label: Should integrate with current configuration system
        - label: Should follow existing logging and error handling patterns

  - type: textarea
    id: related-features
    attributes:
      label: Related Features
      description: |
        Are there existing features that this would interact with or build upon?
        Reference existing issues, PRs, or documentation if relevant.
      placeholder: |
        This relates to issue #123...
        This would work well with the existing --feature...
        This might conflict with...

  - type: textarea
    id: additional-context
    attributes:
      label: Additional Context
      description: |
        Add any other context, screenshots, examples, or references about the feature request here.
        Include links to similar features in other tools, relevant documentation, etc.
      placeholder: |
        Similar feature in other tools...
        Reference documentation...
        Example configuration files...
        Screenshots or mockups...

  - type: checkboxes
    id: contribution-willingness
    attributes:
      label: Contribution Interest
      description: Would you be interested in helping implement this feature?
      options:
        - label: I would like to implement this feature myself
        - label: I can help with testing the implementation
        - label: I can help with documentation
        - label: I can provide feedback during development
        - label: I prefer to just submit the idea and let others implement it

  - type: markdown
    attributes:
      value: |
        ---
        
        ### 📋 Next Steps
        
        After submitting this feature request:
        
        1. **Triage**: We'll review and label your request within 48 hours
        2. **Discussion**: We may ask follow-up questions or request clarifications
        3. **Planning**: If accepted, we'll add it to our development roadmap
        4. **Implementation**: Development will begin based on priority and complexity
        5. **Testing**: We'll request your help testing the feature when ready
        
        ### 💡 Tips for Better Feature Requests
        
        - **Be specific**: Detailed descriptions help us understand your needs
        - **Provide context**: Explain the problem you're trying to solve
        - **Consider scope**: Features should align with the project's goals
        - **Think about others**: How would this benefit the broader community?
        
        Thank you for helping improve the Debian Auto Upgrade Tool! 🚀
