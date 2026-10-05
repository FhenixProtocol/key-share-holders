# Changelog

One entry per tag. Each entry records the digests that `values.tfvars` pinned for that
release.

`.github/workflows/release.yml` writes the entries. Do not edit them by hand.

## v1.0.3 - 2026-10-05

| Image | Digest | Source commit |
|---|---|---|
| keygen | `sha256:f2ea9c4802236eb0f3f3c42c8c5c6d8f02e062d136f8ac06ef7f34ac64688f69` | `7f93823f135f47b794482b984870b42aef95468d` |
| teecryptor | `sha256:c111fb96307039eea5ff0d3aa808f0146392c099c48bd417b8ac323bd566cbd9` | `852f1160857ae5a81a41df546199156011fe6436` |
| zee-k | `sha256:75265b62e9bc90c7fc4c3ff0b03ba714aefece3796d55fe9c9af7bfaa95a5b2b` | `ad2e30c3f10a4d1c9992d17a4e2d122ab56b272c` |

## v1.0.2 - 2026-09-23

| Image | Digest | Source commit |
|---|---|---|
| keygen | `sha256:78c1f33c60b1eb3a6d8ad657687c05708e44167b18bf599b08f4ab833a43519c` | `01652062b703ca19b11a9959155de9ae21697e21` |
| teecryptor | `sha256:591d0046c306c5ce37c4c604d11b181de707698f2f9432648b16638912c49cfb` | `c5168e102742a31e89ff8f1ca3bd7f98a8c466c9` |
| zee-k | `sha256:291fcd710905cfc3b3ab1f0aa5a8fc062f6de9eb87a2f81674cfeab84bc5beec` | `f3382f20f23a64ae479bc8dfa8eb10990dd20424` |

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
