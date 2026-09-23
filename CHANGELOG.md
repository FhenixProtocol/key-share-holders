# Changelog

One entry per tag. Each entry records the digests that `values.tfvars` pinned for that
release.

`.github/workflows/release.yml` writes the entries. Do not edit them by hand.

## v1.0.1 - 2026-09-23

| Image | Digest | Source commit |
|---|---|---|
| keygen | `sha256:78c1f33c60b1eb3a6d8ad657687c05708e44167b18bf599b08f4ab833a43519c` | `01652062b703ca19b11a9959155de9ae21697e21` |
| teecryptor | `sha256:591d0046c306c5ce37c4c604d11b181de707698f2f9432648b16638912c49cfb` | `c5168e102742a31e89ff8f1ca3bd7f98a8c466c9` |
| zee-k | `sha256:291fcd710905cfc3b3ab1f0aa5a8fc062f6de9eb87a2f81674cfeab84bc5beec` | `f3382f20f23a64ae479bc8dfa8eb10990dd20424` |

## v1.0.0 - 2026-09-22

| Image | Digest | Source commit |
|---|---|---|
| keygen | `sha256:78c1f33c60b1eb3a6d8ad657687c05708e44167b18bf599b08f4ab833a43519c` | `01652062b703ca19b11a9959155de9ae21697e21` |
| teecryptor | `sha256:591d0046c306c5ce37c4c604d11b181de707698f2f9432648b16638912c49cfb` | `c5168e102742a31e89ff8f1ca3bd7f98a8c466c9` |
| zee-k | `sha256:291fcd710905cfc3b3ab1f0aa5a8fc062f6de9eb87a2f81674cfeab84bc5beec` | `f3382f20f23a64ae479bc8dfa8eb10990dd20424` |

## v0.1.0 - 2026-08-31

Genesis. The partner Terraform, the read-only operator grant, the guide, CI, and the
release automation. Placeholders only: no rendered `values.tfvars` yet.

- `partner/`: the two secrets and the attestation gates on them, plus `verify/`.
- `access/`: the two read-only viewer roles for the Fhenix operator group.
- `PARTNER_GUIDE.md`: the onboarding guide; the single source (Notion links here).
- `.github/workflows/ci.yml`: `terraform fmt -check` and `validate`; no credentials.
- `.github/workflows/release.yml`: renders a release, opens its PR, tags on merge.
- `EXPECTED.md` states the exact before/after against the previous tag. You check an
  upgrade value by value, not by shape.
