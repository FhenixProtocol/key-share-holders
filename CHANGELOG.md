# Changelog

One entry per tag. Each entry records the digests that `values.tfvars` pinned for that
release.

`.github/workflows/release.yml` writes the entries. Do not edit them by hand.

## v0.1.0 — 2026-08-31

Genesis. The partner Terraform, the read-only operator grant, the guide, CI, and the
release automation. Placeholders only — no rendered `values.tfvars` yet.

- `partner/` — the two secrets and the attestation gates on them, plus `verify/`.
- `access/` — the two read-only viewer roles for the Fhenix operator group.
- `PARTNER_GUIDE.md` — the onboarding guide; the single source (Notion links here).
- `.github/workflows/ci.yml` — `terraform fmt -check` and `validate`; no credentials.
- `.github/workflows/release.yml` — renders a release, opens its PR, tags on merge.
- `EXPECTED.md` states the exact before/after against the previous tag. You check an
  upgrade value by value, not by shape.
