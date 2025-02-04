# Security Policy

## Handling Sensitive Data

1. Never commit sensitive data to the repository:
   - API keys
   - Firebase configuration files
   - Passwords
   - Private certificates
   - Environment files

2. Use Configuration.swift for sensitive data:
   - Copy ConfigurationTemplate.swift to Configuration.swift
   - Add your local values
   - Configuration.swift is gitignored

3. Required local setup:
   - Request GoogleService-Info.plist from team lead
   - Copy ConfigurationTemplate.swift to Configuration.swift
   - Add required values to Configuration.swift

## Reporting Security Issues

If you discover a security vulnerability, please:
1. DO NOT create a public issue
2. Email [your-security-email] 

## Checking for Exposed Secrets

1. Run the repository scanner:
   ```bash
   ./scan-repo.sh
   ```

2. If sensitive data is found:
   - Do not commit any new changes
   - Contact the security team immediately
   - Do not push to remote if found locally

3. To remove sensitive data:
   - Use the provided remove-sensitive-data.sh script
   - Force push changes after removal
   - Have all team members reclone the repository 