# Releasing

**For Fhenix.** If you are a partner, you want [`PARTNER_GUIDE.md`](./PARTNER_GUIDE.md).

A release is one dispatch. You type no file by hand.

## 1. Build the images you are changing

Run the build workflow from `main` in each repo you are releasing:

- [`cofhe-tdx-keygen`](https://github.com/FhenixProtocol/cofhe-tdx-keygen): `build-keygen-tdx.yml`
- [`teecryptor`](https://github.com/FhenixProtocol/teecryptor): `build-teecryptor.yml`
- [`zee-k-verifier`](https://github.com/FhenixProtocol/zee-k-verifier): `build-zk-verifier-tdx.yml`

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

**Leave an unchanged image empty.** The workflow carries its pin forward from the previous
tag. The first release has nothing to carry, so it needs all six values.

A digest and its commit carry forward independently. Fill both or neither: filling only
the digest keeps the old commit, and the run then fails at the proof step with what looks
like an attestation problem.

**`keep_previous_readers`** (default `true`) keeps each reader's previous digest next to
the new one, so running consumers keep their read access while an upgrade rolls out. A
reader then lists 2 images: the new one, and the previous release's one, marked
*previous*. A reader you leave empty keeps the previous release's list unchanged, 1 or 2
images, so a release that moves only another image does not end an upgrade. Set it to
`false` in the release after the upgrade finished and works: each reader then keeps only
its newest digest. `PARTNER_GUIDE.md` calls these two releases tag A and tag B.

While an upgrade is open, a new tag A keeps the image that still runs: over a previous
list `[p0, p1]`, a new digest renders `[new, p1]`. Release tag B after a successful roll,
before any new upgrade.

Before a fix-forward release, roll every pod back to the older image of the overlap.
Check that each pod restarts. See `RESHARE.md`.

<!-- FIRST-LIST-RELEASE -->
The first release with digest lists must keep each reader's live digest. Over a previous
release with one digest per reader, the run refuses `false`.

The compute project is not a dispatch input. It comes from the repository variable
`FHENIX_COMPUTE_PROJECT`, and the run fails if it is unset.

The workflow then:

- rejects a malformed tag, digest or commit, and a tag that exists
- **proves each digest came from the commit beside it**, the kept previous ones too. This catches a wrong commit
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

Do not try to read the files in `partner/bundles`. They are machine-readable signatures.
The step above proved them, and every partner apply proves them again.

**Do not rename the pull request.** The tag job reads the tag out of its title.

Merging tags `main`, creates the GitHub Release, and puts the source-tarball sha256 into
the release notes.

## 4. Send partners the tag

The tag only. No files, no digests in a message. The tag carries everything.

## Key ceremonies are not releases

A release pins images. It never grants write access. `values.tfvars` does not carry
`grant_write_access`, and the module default is `false`.

Write access is an apply-time flag. Around a ceremony you ask the partner to apply with
`-var grant_write_access=true`, and to re-apply without it afterwards. That is the same
pair of commands we run against our own staging projects. No release is involved, and
no tag records it.

## First release versus later ones

Your steps do not change. These things differ:

- The first release has no previous tag, so `EXPECTED.md` carries no diff table, and you
  supply all six values.
- A partner onboards on the first tag, which takes 1 to 2 hours. Later tags take about 5
  minutes.
- A later release may destroy a read binding. That is normal when an upgrade ends
  (`keep_previous_readers = false`). See *Apply a later release* in `PARTNER_GUIDE.md`.
- <!-- FIRST-LIST-RELEASE --> The first release with image lists moves the read
  bindings to a new resource. See *The first release with image lists* in
  `PARTNER_GUIDE.md`.

Adding a **fourth** consumer image is a code change here, not a dispatch input. The image
names live in `partner/verify-image.sh` and in a validation in `partner/variables.tf`.

## Never delete a pinned image

Each partner apply proves every pinned digest against its build attestation, and that
needs the image in the public registry. The registry repositories have no cleanup
policy. Do not delete an image that any release pins. A rollback also repins old
images.

## Cleanup after the first list release

Some code and text exist only for the move to image lists. Each place carries the tag
`FIRST-LIST-RELEASE`: a comment in code, `<!-- FIRST-LIST-RELEASE -->` in Markdown.

When every partner on mainnet, testnet and staging has applied a release with image
lists:

1. Run `git grep -n FIRST-LIST-RELEASE`.
2. Remove each tagged place. The tag comment says what goes.
3. Remove this section.

The root `values.tfvars` and `EXPECTED.md` carry no tag: the next release renders them
again.
