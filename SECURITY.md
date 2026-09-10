# Security Policy

## Trust model

This repository is the Terraform a CoFHE key-custody partner applies in their
own Google Cloud project. It provisions the partner's **attested write-gate**:
the Workload Identity pool, provider, and CEL that decide who may write the
partner's key share — only the exact pinned, attested keygen enclave can. The
design is built to be verified, not trusted: the repo is public so a partner
(or anyone) can review the policy they are applying before they apply it.

## Reporting a vulnerability

Report security issues **privately** — do not open a public issue or PR.

- Preferred: GitHub private vulnerability reporting (the repository's
  **Security** tab → "Report a vulnerability").

Include a description, reproduction steps, and impact. We acknowledge reports
promptly and coordinate disclosure with you.

## Security review

This codebase is under continuous security review: every change to a security
control gets adversarial review before it lands, and findings are tracked to
resolution.
