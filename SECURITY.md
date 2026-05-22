# Security Policy

## Supported projects

Security fixes are applied to the default branch of this repository.

## Secret handling

This repository is public. Do not commit production secrets, API tokens, private
keys, database URLs with real passwords, Redis URLs with real passwords, AWS
access keys, SMTP credentials, Rails master keys, or decrypted Rails
credentials.

Use `.env.sample` only as a placeholder template. Store real production values
in Fly secrets, Rails credentials, your container orchestrator, or another
secret manager.

## Reporting a vulnerability

Please do not report security vulnerabilities through public GitHub issues.

Report privately by email:

- `support@logister.org`

Include:

- Affected component and version/commit
- Reproduction steps or proof of concept
- Impact assessment
- Suggested mitigation (if available)

We will acknowledge receipt and follow up with remediation status.
