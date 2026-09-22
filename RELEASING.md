# Releasing

**For Fhenix.** If you are a partner, you want [`PARTNER_GUIDE.md`](./PARTNER_GUIDE.md).

A release is one dispatch. You type no file by hand.

## 1. Build the images you are changing

Run the build workflow from `main` in each repo you are releasing:

- [`cofhe-tdx-keygen`](https://github.com/FhenixProtocol/cofhe-tdx-keygen)
- [`teecryptor`](https://github.com/FhenixProtocol/teecryptor)
- [`zee-k-verifier`](https://github.com/FhenixProtocol/zee-k-verifier)

Each run summary prints two values: `image_digest` and `source_sha`. Take both.

> **Check the summary shows a handoff block.** If it shows **NO ATTESTATION — DO NOT
> HAND THIS TO A PARTNER**, the attestation failed. Re-run the build. That digest has no
> provenance, so every partner apply rejects it.

Never release a `dev-*` build. It carries a real attestation, so the partner check passes.
Only you know it is not a release.

## 2. Dispatch `release.yml`

Actions → **release** → Run workflow. Fill in:

- the tag, as `vX.Y.Z`
- the digest and commit of each image **you changed**
- `Ceremony release`, only when a key ceremony follows

**Leave an unchanged image empty.** The workflow carries its pin forward from the previous
tag. The first release has nothing to carry, so it needs all six values.

The workflow then:

- rejects a malformed tag, digest or commit, and a tag that exists
- **proves each digest came from the commit beside it** — this catches a wrong commit
  here, once, instead of at every partner
- renders `values.tfvars` and `EXPECTED.md`, with the diff against the previous tag
- type-checks the rendered file against the real variables
- writes the `CHANGELOG.md` entry
- opens a `release/vX.Y.Z` pull request

The run summary lists each pin and says whether you supplied it or it was carried forward.
Read that table.

## 3. Review and merge

Compare `values.tfvars` and `EXPECTED.md` against the build summaries. Then merge.

Merging tags `main`, creates the GitHub Release, and puts the source-tarball sha256 into
the release notes.

## 4. Send partners the tag

The tag only. No files, no digests in a message. The tag carries everything.

## The ceremony flag

Set `Ceremony release` for the release **before** a key ceremony. It adds
`grant_write_access = true`, which lets our enclave write each share once.

**The next release must clear it.** Applying that release removes the write binding. The
partner's plan then shows exactly 2 destroys. See `PARTNER_GUIDE.md` step 11.

## First release versus later ones

Your steps do not change. Three things differ:

- The first release has no previous tag, so `EXPECTED.md` carries no diff table, and you
  supply all six values.
- A partner onboards on the first tag, which takes 1 to 2 hours. Later tags take about 5
  minutes.
- A later release may destroy a read binding. That is normal when a consumer image
  rotates. See *Apply a later release* in `PARTNER_GUIDE.md`.

## Order that matters

Do not release before the image builds emit attestations. The dispatch proves every pair,
so a digest built without provenance stops the release. That refusal is correct.
