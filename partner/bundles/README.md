# Attestation bundles

One signed SLSA build provenance attestation per image digest that this release pins.
`release.yml` proves each digest, then commits the exact bundle that passed.

The file name is `<image>-<digest without the sha256: prefix>.jsonl`. The digest is in
the name, so a bundle from another release can never stand in for this one:
`verify-image.sh` looks for the exact file, and downloads from `api.github.com` when it
is absent.

**Do not edit these files.** That we ship them grants us nothing. `gh` checks each
bundle's signature, the identity in its certificate and the digest it names against
Sigstore's public trust root. A file we changed fails, and your apply stops.

The same bundles are public at
`https://api.github.com/repos/FhenixProtocol/<repo>/attestations/<digest>`.
