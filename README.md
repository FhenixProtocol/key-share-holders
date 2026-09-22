# CoFHE key-share holders — the partner Terraform

This repository is the Terraform that a CoFHE key-custody partner applies in their own
GCP project. It is the **source of truth**: there is no zip, no mirror, and no second
copy. Every partner applies the same files at the same tag.

Nothing here runs a service. Two `terraform apply` commands in your own project are the
complete partner side.

Read `PARTNER_GUIDE.md` first. The step numbers below refer to that guide.

`RELEASING.md` is for Fhenix, not for you. It records how we cut a release, so you can
see how the files you apply are produced.

## How a release works

A release is a **tag**. Each tag carries one `values.tfvars` at the repository root. It holds the shared
values of that release: the Fhenix compute project, the three image digests, and the commit each image was built from. The file is overwritten by every release; the tag is what makes a version
retrievable.

```bash
git clone https://github.com/FhenixProtocol/key-share-holders
cd key-share-holders
git fetch --tags && git checkout v0.1.0
```

Check what you got against the GitHub Release notes for that tag, which carry the
sha256 of the source tarball:

```bash
curl -sL https://github.com/FhenixProtocol/key-share-holders/archive/refs/tags/v0.1.0.tar.gz | shasum -a 256
```

`EXPECTED.md` at the root states what your plan and your `verify/` run must show for
that release. To see what changed between two releases:

```bash
git log -p v0.1.0..v0.2.0 -- values.tfvars
```

`CHANGELOG.md` says the same thing in prose, for reading on GitHub without git.

## Contents

```
PARTNER_GUIDE.md   the onboarding guide. Start here.
CHANGELOG.md       one entry per tag: what changed, which digests
values.tfvars      the shared values of the current release (added at the first real release)
EXPECTED.md        what your plan and verify must show for those values
access/            step 4 — gives Fhenix READ-ONLY visibility in your project
partner/           steps 5 to 6 — your two secrets and the attestation gates on them
  verify-image.sh  proves a digest came from the commit beside it, before it is pinned
                   (SLSA build provenance; needs gh, jq and curl, no GitHub account)
  provenance.tf    runs that proof on every plan and apply. A failure stops the run.
  verify/          step 6 — read-only check of what landed (no resources)
  modules/partner-onboarding/   the module. partner/ is a thin root around it.
```

## What `partner/` creates (about 15 resources, 0 destroys)

| Resource | Purpose |
|---|---|
| 2 Secret Manager secrets `cofhe-tee-fhe-priv`, `cofhe-tee-zk-signer` | Your share of the FHE private key (with the decrypt signer) and of the zk signer. Both have `prevent_destroy`. |
| Workload Identity pool + provider `cofhe-tee-keygen-pool` / `-provider` | The **write** gate. The CEL requires genuine Intel TDX Confidential Space, the STABLE image tier, the Fhenix compute project, and the exact keygen image digest. |
| Reader pool + 2 providers `cofhe-tee-reader-pool` / `teecryptor-reader`, `zee-k-reader` | The **read** gates. Same CEL, plus `dbgstat == "disabled-since-boot"`, pinned to the exact image digest of each consumer. |
| `secretVersionAdder` × 2 → attested keygen principal | Append-only write. Present only while `grant_write_access = true` (the ceremony window). |
| `secretAccessor` × 2 → attested consumer principals | Each consumer image can read **only** its own secret. |
| Secret Manager Data Access audit config | Each read of a share is logged in your project, with the identity that made it. |

The exact CEL strings are in `partner/modules/partner-onboarding/main.tf` (`locals`).
Each IAM member is a `principalSet://…/attribute.image_digest/sha256:…`. There is no
`user:` and no `serviceAccount:`.

## What `access/` creates (2 bindings)

`roles/secretmanager.viewer` and `roles/iam.workloadIdentityPoolViewer`, bound to the
Fhenix operator group, in this project only. Both are Google-predefined roles. With
them, we can confirm your CEL pins and see that a ceremony landed (version *metadata*).
They cannot read a secret value. They cannot change IAM. `access/main.tf` explains why
we do not take more. It also explains why we tried a time-limited write permission
and then rejected it.

## What you run

```bash
# one time: state bucket in your project
gcloud storage buckets create gs://<your-project>-tfstate --uniform-bucket-level-access

# steps 3 and 4: get the release, then grant read-only access
git clone https://github.com/FhenixProtocol/key-share-holders
cd key-share-holders && git fetch --tags && git checkout <tag>

cd access && terraform init -reconfigure -input=false \
  -backend-config="bucket=<your-project>-tfstate" -backend-config="prefix=cofhe-tdx-keygen/access" \
  && terraform apply -var="partner_project_id=<your-project>"

# steps 5 to 6
cd ../partner && terraform init -reconfigure -input=false \
  -backend-config="bucket=<your-project>-tfstate" -backend-config="prefix=cofhe-tdx-keygen/partner" \
  && terraform plan  -var-file=../values.tfvars -var partner_project_id=<your-project> \
  && terraform apply -var-file=../values.tfvars -var partner_project_id=<your-project>

terraform -chdir=verify init -backend=false -input=false \
  && terraform -chdir=verify plan -input=false \
       -var-file=../../values.tfvars -var partner_project_id=<your-project>   # step 6: expect a SUCCESS block

terraform output -json > <your-project>-outputs.json   # step 7: send this file to us
```

After the ceremony, you apply again with the next tag, whose `values.tfvars` has no
`grant_write_access = true`. The plan shows exactly two destroys (the write bindings).
Your secrets are then frozen.

## The one value you supply

`partner_project_id` — your own GCP project. You pass it on the command line, as above.
This repository never stores it, and no file here holds it. Everything else comes from
`values.tfvars` at the tag you checked out.

## Placeholders

`<your-project>` is yours. `fhenix-compute-project` is a placeholder for the Fhenix
compute project. The first real release puts the real project id in `values.tfvars`. The `sha256:<…>` digests in the examples are placeholders for the
same reason. You type none of them.

## Status of this code

This code is live on the Fhenix staging environment (5 partners, 2-of-5) and on the
testnet environment (3 partners, 2-of-3). Comments in `variables.tf` record why
`grant_write_access` defaults to false. They stay as history, so you can audit the reasoning.
