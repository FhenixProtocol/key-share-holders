# Attestation bundles

This directory holds the signed proof for each image digest that this release pins.
`release.yml` proves each digest. It then commits the attestation for each digest that
this release adds. A digest that carries forward keeps the file from the earlier tag.

The file name is `<image>-<digest without the sha256: prefix>.jsonl`. The digest is part
of the name. A file from another release can thus never replace this one.
`verify-image.sh` looks for the exact name. If that file is absent, the script downloads
the attestation from `api.github.com`. If the file is present but empty, the script stops
and tells you to get the release tag again.

A file holds every attestation that GitHub published for that digest. One attestation is
on each line. The script asserts several fields. `gh` selects the attestation that
matches all the fields.

**Do not change these files.** We give them to you, and this gives us no advantage. `gh`
checks three things against the public trust roots, which we do not control:

- the signature in the file
- the identity in the certificate
- the digest that the file names

A file that we changed fails the check, and your apply stops.

To compare a file against the public record:

```bash
curl -s https://api.github.com/repos/FhenixProtocol/<repo>/attestations/<digest> \
  | jq -c '.attestations[].bundle'
```

There is one difference from that record. A file here keeps its proof after GitHub stops
serving it. This design has no revocation, so the two prove the same thing.

To read the public record instead of this file, set `FHENIX_IGNORE_SHIPPED_BUNDLE=1`
before you run `verify-image.sh`.
