# Releasing

**For Fhenix.** If you are a partner, you want [`PARTNER_GUIDE.md`](./PARTNER_GUIDE.md).

A release is one dispatch. You type no file by hand.

## 1. Build the images you are changing

Run the build workflow from `main` in each repo you are releasing:

- [`cofhe-tdx-keygen`](https://github.com/FhenixProtocol/cofhe-tdx-keygen) — `build-keygen-tdx.yml`
- [`teecryptor`](https://github.com/FhenixProtocol/teecryptor) — `build-teecryptor.yml`
- [`zee-k-verifier`](https://github.com/FhenixProtocol/zee-k-verifier) — `build-zk-verifier-tdx.yml`

The partner check names these exact workflow files. An image built by any other workflow
in the same repo fails the proof.

Each run summary prints two values: `image_digest` and `source_sha`. Take both.

> **Check the summary shows a handoff block.** If it shows **NO ATTESTATION — DO NOT
> HAND THIS TO A PARTNER**, the attestation failed. Re-run the build. That digest has no
> provenance, so every partner apply rejects it.

Never release a `dev-*` build. These workflows run only on `main`, so a `dev-*` tag still
produces a real attestation and the partner check passes. Only you know it is not a
release.

## 2. Dispatch `release.yml`

Actions → **release** → Run workflow. Fill in:

- the tag, as `vX.Y.Z`
- the digest and commit of each image **you changed**
- `Ceremony release`, only when a key ceremony follows

**Leave an unchanged image empty.** The workflow carries its pin forward from the previous
tag. The first release has nothing to carry, so it needs all six values.

A digest and its commit carry forward independently. Fill both or neither: filling only
the digest keeps the old commit, and the run then fails at the proof step with what looks
like an attestation problem.

The compute project is not a dispatch input. It comes from the repository variable
`FHENIX_COMPUTE_PROJECT`, and the run fails if it is unset.

The workflow then:

- rejects a malformed tag, digest or commit, and a tag that exists
- **proves each digest came from the commit beside it** — this catches a wrong commit
  here, once, instead of at every partner
- commits each attestation in `partner/bundles`. A partner's apply then reads the proof
  from the tag, and calls no GitHub API
- renders `values.tfvars` and `EXPECTED.md`, with the diff against the previous tag
- type-checks the rendered file against the real variables
- writes the `CHANGELOG.md` entry
- opens a `release/vX.Y.Z` pull request

The run summary lists each pin and says whether you supplied it or it was carried forward.
Read that table.

## 3. Review and merge

Compare `values.tfvars` and `EXPECTED.md` against the build summaries. Then merge.

Do not try to read the files in `partner/bundles`. They are signed data, not text. The
step above proved them, and every partner apply proves them again.

**Do not rename the pull request.** The tag job reads the tag out of its title.

Merging tags `main`, creates the GitHub Release, and puts the source-tarball sha256 into
the release notes.

## 4. Send partners the tag

The tag only. No files, no digests in a message. The tag carries everything.

## The ceremony flag

Set `Ceremony release` for the release **before** a key ceremony. It adds
`grant_write_access = true`, which lets our enclave write each share once.

**The next release must clear it.** Applying that release removes the write binding. The
partner's plan then shows exactly 2 destroys. See `PARTNER_GUIDE.md` step 11.

**That release changes no image.** Leave all six image fields empty so every pin carries
forward. Rotating an image in the same release adds destroys of its own, and the partner
is told to stop when the count is not exactly 2.

## First release versus later ones

Your steps do not change. Three things differ:

- The first release has no previous tag, so `EXPECTED.md` carries no diff table, and you
  supply all six values.
- A partner onboards on the first tag, which takes 1 to 2 hours. Later tags take about 5
  minutes.
- A later release may destroy a read binding. That is normal when a consumer image
  rotates. See *Apply a later release* in `PARTNER_GUIDE.md`.

Adding a **fourth** consumer image is a code change here, not a dispatch input. The image
names live in `partner/verify-image.sh` and in a validation in `partner/variables.tf`.

