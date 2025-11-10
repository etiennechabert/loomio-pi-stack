# Contributing to Loomio Pi Stack

Thank you for considering contributing to the Loomio Pi Stack! This document outlines the process and guidelines.

## How Can I Contribute?

### Reporting Bugs

Before submitting a bug report:
- Check existing [issues](https://github.com/etiennechabert/loomio-pi-stack/issues)
- Verify you're using the latest version
- Test with default configuration

**Bug reports should include:**
- Clear description of the issue
- Steps to reproduce
- Expected vs actual behavior
- Environment details (OS, Docker version, hardware)
- Relevant logs (`docker compose logs`)

### Suggesting Enhancements

Enhancement suggestions are welcome! Please:
- Check if it's already suggested
- Explain the use case clearly
- Consider if it fits the project scope
- Provide examples if applicable

### Pull Requests

1. **Fork the repository**
   ```bash
   git clone https://github.com/etiennechabert/loomio-pi-stack.git
   ```

2. **Create a feature branch**
   ```bash
   git checkout -b feature/my-new-feature
   ```

3. **Make your changes**
   - Follow existing code style
   - Update documentation
   - Test thoroughly

4. **Run pre-commit checks**
   ```bash
   ./scripts/pre-commit-check.sh
   ```

5. **Commit your changes**
   ```bash
   git commit -m "Add feature: description"
   ```

6. **Push to your fork**
   ```bash
   git push origin feature/my-new-feature
   ```

7. **Open a Pull Request**
   - Describe what changed and why
   - Reference related issues
   - Include testing steps

## Development Guidelines

### Docker Compose Changes

- Validate syntax: `docker compose config`
- Test on Raspberry Pi if possible
- Document new environment variables in `.env.example`
- Update relevant documentation

### Documentation

- Use clear, concise language
- Include examples
- Update table of contents
- Test all commands before documenting

### Scripts

- Use bash for shell scripts
- Add error handling (`set -e`)
- Include comments for complex logic
- Make scripts executable: `chmod +x script.sh`
- Test on both x86_64 and ARM architectures

### Python Code (Backup Service)

- Follow PEP 8 style guide
- Add docstrings for functions
- Include error handling
- Test encryption/decryption thoroughly

## Testing

### Manual Testing Checklist

- [ ] Fresh installation works (QUICKSTART.md)
- [ ] Backup creation succeeds
- [ ] Backup restoration works
- [ ] All containers start healthy
- [ ] Web interface accessible
- [ ] Email sending works
- [ ] Auto-updates function (Watchtower)
- [ ] Monitoring dashboard loads (Netdata)

### Test on Multiple Platforms

- Raspberry Pi 4 (ARM)
- Linux x86_64
- macOS (if applicable)

## Code Style

### Shell Scripts

```bash
#!/bin/bash
# Script description

set -e  # Exit on error

# Clear variable names
BACKUP_DIR="/backups"

# Functions with descriptions
function create_backup() {
    # Function description
    echo "Creating backup..."
}
```

### Python

```python
#!/usr/bin/env python3
"""
Module description
"""

import os
import sys

def function_name():
    """Function description"""
    pass
```

### Markdown

- Use ATX-style headers (`#` not `===`)
- Include table of contents for long documents
- Use code blocks with language specification
- Keep lines under 120 characters when possible

## Commit Messages

Follow conventional commits:

```
type(scope): subject

body (optional)

footer (optional)
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Formatting, missing semicolons, etc.
- `refactor`: Code restructuring
- `test`: Adding tests
- `chore`: Maintenance tasks

**Examples:**

```
feat(backup): add Google Drive integration

Implements automatic backup uploads to Google Drive using service accounts.
Includes retry logic and error handling.

Closes #42
```

```
fix(docker): correct health check timeout

The app container health check was timing out too early.
Increased timeout from 10s to 30s to allow for slower startup.
```

## Project Structure

```
loomio-pi-stack/
├── backup-service/          # Backup Docker image
│   ├── Dockerfile
│   ├── backup.py
│   ├── entrypoint.sh
│   └── requirements.txt
├── scripts/                 # Utility scripts
│   ├── restore-db.sh
│   ├── restore-on-boot.sh
│   ├── pre-commit-check.sh
│   └── watchdog/
│       └── health-monitor.sh
├── monitoring/              # Monitoring configuration
│   └── netdata/
│       ├── health.d/
│       └── go.d/
├── .github/                 # CI/CD workflows
│   └── workflows/
│       └── ci.yml
├── docker-compose.yml       # Main stack definition
├── .env.example             # Environment template
├── *.service                # Systemd units
├── README.md                # Main documentation
├── QUICKSTART.md            # Setup guide
├── BACKUP_GUIDE.md          # Backup documentation
├── SECURITY.md              # Security guidelines
├── RESTORE_ON_BOOT.md       # Stateless operation
└── CONTRIBUTING.md          # This file
```

## Security

### Reporting Security Issues

**DO NOT** open public issues for security vulnerabilities.

Instead:
- Email: security@example.com (or create private security advisory on GitHub)
- Include detailed description
- Provide steps to reproduce
- Suggest a fix if possible

We'll respond within 48 hours.

### Security in Code

- Never commit secrets or credentials
- Use environment variables for sensitive data
- Encrypt sensitive data at rest
- Validate all user input
- Use official Docker images when possible
- Keep dependencies updated

## Review Process

1. **Automated Checks**
   - CI pipeline must pass
   - No security vulnerabilities
   - Docker compose validates
   - Scripts are executable

2. **Manual Review**
   - Code quality
   - Documentation completeness
   - Testing coverage
   - Security implications

3. **Testing**
   - Reviewer tests changes
   - Feedback provided
   - Revisions if needed

4. **Merge**
   - Approved by maintainer
   - Squash or rebase
   - Update changelog

## Questions?

- Open a [Discussion](https://github.com/etiennechabert/loomio-pi-stack/discussions)
- Join Loomio community
- Check existing documentation

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

**Thank you for contributing!** 🎉
