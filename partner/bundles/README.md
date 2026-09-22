# Attestation bundles

This directory holds the signed proof for each image digest that this release pins.
`release.yml` proves each digest. It then commits the attestations that it used.

The file name is `<image>-<digest without the sha256: prefix>.jsonl`. The digest is part
of the name. A file from another release can thus never stand in for this one:
`verify-image.sh` looks for the exact name. If that file is absent, the script downloads
the attestation from `api.github.com`.

A file holds every attestation that GitHub published for that digest, one for each line.
`gh` selects the attestation that agrees with all of the fields that the script asserts.

**Do not change these files.** We give them to you, and this gives us no advantage. `gh`
checks the signature in the file, and the identity in the certificate, and the digest
that the file names. It does all three against the public trust roots, which we do not
control. A file that we changed fails the check, and your apply stops.

To compare a file against the public record:

```bash
gh api repos/FhenixProtocol/<repo>/attestations/<digest> --jq '.attestations[].bundle'
```

One difference from that record: a file here keeps its proof after GitHub stops serving
it. This design has no revocation, so the two are equal in what they prove.
