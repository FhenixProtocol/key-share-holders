# Partner Dev: Initialization

You check out the release tag we send you. It already carries the configuration file.
You apply. This creates two Secret Manager entries and the IAM rules that decide
**which attested Fhenix enclave can write your key share, and which can read it**.

**Time: 1 to 2 hours, one time.** After this, nothing runs on your side. We are on the
call with you.

> **We send you one thing: a release tag in this repository.**
> The tag carries everything: the Terraform, this guide, the `values.tfvars` with
> every shared value already filled in, and the `EXPECTED.md` that lists the exact
> strings your checks must show. Every partner gets the same tag.
>
> **You run each apply in your project. We cannot.** Fhenix has read-only access to
> your project. We check and we advise; you execute. This is by design. The Terraform
> that sets the IAM on your secrets needs one permission
> (`secretmanager.secrets.setIamPolicy`). The holder of that permission can give
> read access on a share to itself. We do not take it. See [step 4](#4-give-fhenix-read-only-access).

## 1. Prerequisites

Make sure you followed PROJECT_CREATION.md and filled the form at https://forms.gle/8XjawvVSWZSGCg45A

**Set these two first.** Every command below uses them, so you substitute nothing by hand:

```bash
export PROJECT=<your GCP project id>
export TAG=<the tag we sent you>        # for example v1.0.2
```

They live in your shell, so set them again in any new terminal.

- `terraform` 1.9 or later, and `gcloud`.
- `gh` **2.68** or later, plus `jq` and `curl`. Your apply uses `gh` to prove where each
  image came from, before it pins anything. `jq` and `curl` are only for the fallback,
  which a normal apply does not use. Install with `brew install gh jq`, or see
  https://github.com/cli/cli#installation. Check with `gh --version`. Version 2.68 added
  the flags that this check needs. An older `gh` stops with a clear message.
  **You do not need a GitHub account and you do not need to run `gh auth login`.**
- Network access from the machine that runs terraform to these hosts:

  | Host | What it gives | Used |
  |---|---|---|
  | `europe-west4-docker.pkg.dev` | the image, to confirm the digest resolves | always |
  | `tuf-repo-cdn.sigstore.dev` | Sigstore's public trust root | always |
  | `tuf-repo.github.com` | GitHub's public trust root | always |
  | `api.github.com` | the attestation for a digest the tag does not carry | fallback |

  The two trust roots are the public record, and we do not control them. Your check
  tests our file against them.

The release tag carries the signed attestation for every digest it pins, in
`partner/bundles`. Your apply reads those files, so it calls no GitHub API. The one
exception is a digest that the tag does not carry, which you only meet if you check an
image by hand.

We give you the file. This gives us no advantage. `gh` checks three things against the
public trust roots above, which we do not control:

- the signature in the file
- the identity in the certificate
- the digest that the file names

A file that we changed fails the check.

You do not have to take our copy. [Check a digest yourself](#check-a-digest-yourself) fetches
the same attestation from GitHub instead. It is optional: your apply proves the images
either way.

## 2. Create your Terraform state bucket

```bash
gcloud storage buckets create gs://$PROJECT-tfstate \
  --project=$PROJECT --uniform-bucket-level-access
```

## 3. Get the release

We send you one thing: a release tag in this repository. Get it, and confirm it is what
we published. Everything from here on runs from inside this clone.

```bash
git clone https://github.com/FhenixProtocol/key-share-holders
cd key-share-holders
git fetch --tags && git checkout $TAG
```

Confirm you are on that tag, and that nothing is modified:

```bash
git describe --tags --exact-match   # expect: $TAG
git status --porcelain              # expect: no output
```

The GitHub Release page for the tag also carries the sha256 of its source tarball. You may
compare it:

```bash
curl -fsSL "https://github.com/FhenixProtocol/key-share-holders/archive/refs/tags/$TAG.tar.gz" \
  -o /tmp/src.tar.gz && shasum -a 256 /tmp/src.tar.gz
```

The two commands above check what you will apply. This one checks what we published.

### What the release carries

Four things, at the root of the clone:

- **`EXPECTED.md`**: every value this release pins, and what your `plan` and your
  `verify/` run must show. This is the file you check against.
- **`values.tfvars`**: the shared values themselves. You pass it with `-var-file`; you do
  not edit it, and the `git status --porcelain` above already proves it is byte-identical
  to what we tagged. Your own project id is **not** in it, and is in no file. You pass
  that with `-var partner_project_id=$PROJECT` on every command below.
- **`partner/bundles/`**: one signed attestation for each pinned digest. Your apply reads
  them. You do not touch them. See `partner/bundles/README.md`.
- **`partner/modules/partner-onboarding/`**: the module itself. Read its README before you
  apply. This module *is* the partner side: there is no binary and no service in this
  design.

`values.tfvars` never grants write access. That is an apply-time flag, and it appears only
around a key ceremony. See [step 8](#8-grant-write-access) to [step 11](#11-revoke-write-access).

### Where each image came from

`source_sha` is the commit each image was built from. Both `terraform plan` and
`terraform apply` check the SLSA build provenance of every digest against the public
Sigstore log, before anything is pinned. A digest that did not come from the commit beside
it fails, and nothing is written. You do not have to do anything for this to happen.

To run that check on its own, see [Check a digest yourself](#check-a-digest-yourself).

There is no other read path. Each read of your share goes through these gates, and the
module has no input that gives read access to a person or to a service account.

## 4. Give Fhenix read-only access

With this access we can check your configuration without asking you. It applies to
onboarding and to every release after it.

Two **Google-predefined** roles, on this project only:

| Role | What it permits | What it does not permit |
|---|---|---|
| `roles/secretmanager.viewer` | See that a version exists, and when. This shows us that a ceremony completed. | Read the value (`versions.access`). Change IAM. |
| `roles/iam.workloadIdentityPoolViewer` | Read your deployed CEL. This shows us the digest pin. | Change anything. |

**These are Google roles, not roles that we made.** Check them in the Google
documentation. Do not accept our description of them.

> **We never hold `secretmanager.secrets.setIamPolicy`.** That is why you run every
> apply. See [Why we do not ask for more](#why-we-do-not-ask-for-more).

**Grant the two roles:**

```bash
cd access
terraform init -reconfigure -input=false \
  -backend-config="bucket=$PROJECT-tfstate" \
  -backend-config="prefix=cofhe-tdx-keygen/access" \
  && terraform apply -var="partner_project_id=$PROJECT"
# `operators` defaults to ["group:protocol@fhenix.io"]
```

**Check what we hold, at any time:**

```bash
gcloud projects get-iam-policy $PROJECT \
  --flatten="bindings[].members" \
  --format="value(bindings.role,bindings.members)" | grep protocol@fhenix.io
# expect ONLY: roles/secretmanager.viewer
#              roles/iam.workloadIdentityPoolViewer
```

To revoke, set `grant_view_access = false` in your `access/terraform.tfvars` and apply.
Passing `-var grant_view_access=false` does the same for one command only.

## 5. Init and plan

```bash
cd ../partner        # from access/, where step 4 left you
terraform init -reconfigure -input=false \
  -backend-config="bucket=$PROJECT-tfstate" \
  -backend-config="prefix=cofhe-tdx-keygen/partner" \
  && terraform plan -var-file=../values.tfvars -var partner_project_id=$PROJECT
```

**Correct result:** 16 resources to add. Zero to change. Zero to destroy. Four more are
added if you apply with `-var grant_write_access=true`. We ask for it in
[step 8](#8-grant-write-access), and again only for a reshare.
The count assumes one image per reader. Each second image in `values.tfvars` adds one
read binding.

```
Plan: 16 to add, 0 to change, 0 to destroy.      # 20 with grant_write_access=true

  # google_project_service.apis            -> secretmanager, iam, iamcredentials, sts, cloudresourcemanager
  # google_project_iam_audit_config.secretmanager   -> Data Access logs for Secret Manager
  # google_secret_manager_secret.bundle    -> "cofhe-tee-fhe-priv", "cofhe-tee-zk-signer"
  # google_iam_workload_identity_pool.pool          -> "cofhe-tee-keygen-pool"
  # google_iam_workload_identity_pool_provider      -> "cofhe-tee-keygen-provider"
  # google_iam_workload_identity_pool.reader_pool   -> "cofhe-tee-reader-pool"
  # google_iam_workload_identity_pool_provider.reader -> "teecryptor-reader", "zee-k-reader",
  #                                                       "keygen-reader" (disabled)
  # google_secret_manager_secret_iam_member.attested_add          -> secretVersionAdder   (x2, only with grant_write_access=true)
  # google_secret_manager_secret_iam_member.keygen_version_viewer -> secretmanager.viewer (x2, only with grant_write_access=true)
  # google_secret_manager_secret_iam_member.attested_read_image   -> secretAccessor       (one per reader image)

Changes to Outputs:
  + provenance_verified = { "keygen@<hex>" = {...}, "teecryptor@<hex>" = {...}, "zee-k@<hex>" = {...} }
```

A passing provenance check prints nothing. That `provenance_verified` block is how you
know it ran, and it names the commit proven for each image.

> **If the plan succeeds but shows one of these, stop and contact us:**
> - a *destroy* count that is not zero;
> - a `google_storage_bucket`;
> - a resource in a project that is not yours;
> - fewer than two secrets;
> - an `attested_read_image` binding on the wrong secret.
>
> On this first run a destroy must not appear: there is nothing yet to destroy. A later
> release may legitimately destroy a read binding when an upgrade ends. See
> *Apply a later release*.

**If your plan matches, you are done here. Go on to step 6.** The rest of this step is
troubleshooting.

### If a command fails

**`init` asks "Do you want to migrate all workspaces to gcs?"** Answer **no**. On a new
setup that question must not appear at all, and answering it wrongly overwrites state.
`-input=false` in the command above makes `init` fail instead of asking.

**`init` fails with `Failed to get existing workspaces: querying Cloud Storage failed`.**
Your credentials expired. It is not a wrong bucket name. Run `gcloud auth
application-default login`. Those are separate from `gcloud auth login`.

**`plan` stops with `External Program Execution Failed` on `verify-image.sh`.** Read the
last lines. The script says which of two things happened:

- **`FAIL`**: the proof does not hold. Change nothing. Do not edit a digest or a
  `source_sha` to make it pass. Send us the whole error.
- **`COULD NOT CHECK`**: the check did not finish. This says nothing about the image.
  A host in the table in step 1 was not reachable, or a file in `partner/bundles` is
  damaged. Correct that, then run the plan again.

Nothing is written in either case.

## 6. Apply, then verify

Apply:

```bash
terraform apply -var-file=../values.tfvars -var partner_project_id=$PROJECT
```

Then check what landed:

```bash
terraform -chdir=verify init -backend=false -input=false
terraform -chdir=verify plan -input=false \
  -var-file=../../values.tfvars -var partner_project_id=$PROJECT
```

`verify/` is read-only and creates nothing. It reads the gates and the secret permissions
now live in your project, and compares them with the `values.tfvars` you applied. The full
list of checks is under [Reference](#reference).

**Run it every time, even after a successful apply.** Terraform sees only the bindings it
created. Any other binding on your secrets survives every apply, and `verify/` is the only
step that finds one. It is a separate root, so it needs its own `init` each time,
including in [step 11](#11-revoke-write-access).

**Success:** a `SUCCESS` block, and nothing else.

```
  + SUCCESS = {
      + partner_project      = "$PROJECT"
      + write_gate_pins      = "sha256:…"
      + read_gates_pin       = { teecryptor = ["sha256:…"], zee-k = ["sha256:…"] }
      + reshare_read_granted = false
      + write_access_granted = false
    }
```

Each reader shows a list of 1 or 2 images. Two images are normal while an upgrade is in
progress. `write_access_granted` is `false` here. It becomes `true` only between steps 8
and 11.

**If you see that block, you are done here. Go on to step 7.** The rest of this step is
troubleshooting.

**Failure:** one or more errors. Each error ends with a `CHECK FAILED:` line.

```
CHECK FAILED: an identity that is not an attested enclave can read the share cofhe-tee-fhe-priv.
Unexpected identities: user:someone@example.com
Do not change anything. Send this message to Fhenix.
```

Send us the message. Do not repair anything by hand.

## 7. Send us your outputs

`terraform output` writes to your terminal. Write it to a file and send the file:

```bash
terraform output -json > $PROJECT-outputs.json
```

It holds no secret material. Five values:

- your project id
- the two secret ids
- the audience our keygen enclave attests for
- the audience each consumer enclave attests for
- the proven digest and commit of each image

We compare the project numbers in it with the numbers compiled into our images. If they
differ, the rollout stops on our side, not on yours.

*(We cannot read your Terraform state. The viewer roles have no storage permissions.
You send this file; we do not fetch it.)*

## 8. Grant write access

**Do this only when we ask.** The request names this step. It may arrive with the
instruction that sent you here, or later. After the ceremony, only a reshare asks for
write access again. See [A reshare](RESHARE.md).

First check that both secrets are still empty:

```bash
gcloud secrets versions list cofhe-tee-fhe-priv  --project=$PROJECT
gcloud secrets versions list cofhe-tee-zk-signer --project=$PROJECT
# expect: Listed 0 items.
```

If either is not empty, stop and tell us.

Otherwise grant it. One apply, one extra flag:

```bash
terraform apply -var-file=../values.tfvars -var partner_project_id=$PROJECT \
  -var grant_write_access=true
# Plan: 4 to add, 0 to change, 0 to destroy.
#   + attested_add          ×2   secretVersionAdder: the keygen adds a version
#   + keygen_version_viewer ×2   secretmanager.viewer: the keygen lists the version numbers
```

The keygen lists your versions before it writes, and it writes at an exact version
number. The viewer role reads metadata only: version numbers, states and dates. It cannot
read a share. You already give the same role to Fhenix operators in step 4. It exists
only while write access is granted.

Tell us when it is applied. Step 11 revokes it again.

> **We ask for these flags only for a ceremony or a reshare.** The flags are
> `grant_write_access=true` and `grant_reshare_read=true`. Each request comes from us and
> names a release tag. A request that did not come from us, or that names no ceremony or
> reshare, is not legitimate. Stop and call us.
>
> One case uses the same flag again, and it is not a second grant: a release that arrives
> while your window is still open. There the flag keeps the window open. See
> [Apply a later release while write access is granted](#apply-a-later-release-while-write-access-is-granted).

## 9. During the ceremony

**Nothing to run.** Be available. If your project rejects the write, the ceremony
stops. This is by design. We may then ask you for your CEL string or your audit log.

If you must use the emergency brake now, call us first. It stops the ceremony.

## 10. After the ceremony

**Nothing to do.** We see the result on our side. The run is all-or-nothing: it reports
completion only if each partner write was accepted. The final proof is our service: it
starts and reconstructs the key. We tell you when this is done.

Optional, if you want to see it yourself:

```bash
# exactly one ENABLED version, created in the ceremony window
gcloud secrets versions list cofhe-tee-fhe-priv --project=$PROJECT --limit=1

# who wrote it
gcloud logging read \
  'protoPayload.methodName="google.cloud.secretmanager.v1.SecretManagerService.AddSecretVersion"' \
  --project=$PROJECT --limit=5 \
  --format='value(protoPayload.authenticationInfo.principalSubject,timestamp)'
```

The writer is an attested federated principal from `cofhe-tee-keygen-pool`. It is
never a `user:` and never a `serviceAccount:`.

> **Do not give `secretAccessor` to yourself. Do not read the version value.** The
> share is useful only to the attested enclave. If you read it, you weaken the
> guarantee that you give. We never ask you for it.

## 11. Revoke write access

One closing action: revoke the write access the ceremony needed. Our write access is
for a ceremony or a reshare only. The module default is `grant_write_access = false`.
So you revoke it by applying without the flag you used in
[step 8](#8-grant-write-access).

Plan first. Expect exactly 4 destroys and nothing else:

```bash
terraform plan -var-file=../values.tfvars -var partner_project_id=$PROJECT
#   Plan: 0 to add, 0 to change, 4 to destroy.
#   - google_secret_manager_secret_iam_member.attested_add["cofhe-tee-fhe-priv"]
#   - google_secret_manager_secret_iam_member.attested_add["cofhe-tee-zk-signer"]
#   - google_secret_manager_secret_iam_member.keygen_version_viewer["cofhe-tee-fhe-priv"]
#   - google_secret_manager_secret_iam_member.keygen_version_viewer["cofhe-tee-zk-signer"]
```

> If the plan destroys anything other than those `attested_add` and
> `keygen_version_viewer` bindings, for example a **secret** or an
> `attested_read_image` binding, **do not apply**. Contact us.

Apply:

```bash
terraform apply -var-file=../values.tfvars -var partner_project_id=$PROJECT
```

Then check that write access is gone. This is the step 6 check, now with no write
binding:

```bash
terraform -chdir=verify init -backend=false -input=false
terraform -chdir=verify plan -input=false \
  -var-file=../../values.tfvars -var partner_project_id=$PROJECT
# success: a SUCCESS block with write_access_granted = false
# failure: "CHECK FAILED: the share ... is still writable", or "... has a list binding,
#          but grant_write_access is false". Send it to Fhenix
```

> **Revoked is the default. If you forget this step, the result is safe.** The next apply
> you run for any other reason revokes it, because you will not pass the flag again.
> The old behaviour was the opposite: an absent flag gave write access back, silently.
> That is why we changed the default.

This is reversible. A reshare or a future key rotation asks you for the flag again.
Your read gates do not change. Decryption continues to work.

## The End

---

## Apply a later release

Onboarding happens once. After it, each Fhenix release is the same short loop. Everything
you need is in the tag. There is no other document.

> **Did you run step 8 and not yet step 11?** Then your write access is granted. Use
> [Apply a later release while write access is granted](#apply-a-later-release-while-write-access-is-granted)
> instead. The commands below would close your write window.

**What a release looks like.** We build new images and publish a tag here. The tag carries
a new `values.tfvars` and a new `EXPECTED.md`. Some releases move one image; some move all
three. `EXPECTED.md` names exactly what moved. Here all three changed, and each reader
keeps its previous image next to the new one (a tag A, see below):

```
## What changes from v1.1.0

Changed: keygen, keygen-sha, teecryptor, zee-k

| Pin | v1.1.0 | v1.2.0 | |
|---|---|---|---|
| Fhenix compute project | `fhenix-compute-project` | `fhenix-compute-project` | unchanged |
| keygen (write gate) | `sha256:1111…` | `sha256:aaaa…` | **CHANGED** |
| keygen source commit | `84028ad…` | `b71f004…` | **CHANGED** |
| teecryptor (read gate on cofhe-tee-fhe-priv) | (absent) | `sha256:bbbb…` from `c17ba39…` | **ADDED** |
| teecryptor, previous (read gate on cofhe-tee-fhe-priv) | `sha256:2222…` from `9d20cf4…` | `sha256:2222…` from `9d20cf4…` | unchanged |
| zee-k (read gate on cofhe-tee-zk-signer) | (absent) | `sha256:cccc…` from `e4d8812…` | **ADDED** |
| zee-k, previous (read gate on cofhe-tee-zk-signer) | `sha256:3333…` from `397eca5…` | `sha256:3333…` from `397eca5…` | unchanged |
```

**Apply from the tag, never from `main`.** The `values.tfvars` on `main` is the one of
the last release. It can be in an older shape than the code on `main`, and the next
release renders it again. Only a tag carries a matching pair.

**What you run.** Five minutes, from your existing clone. Set both variables again: a new
terminal has neither, and an old one may still hold the previous tag.

```bash
export PROJECT=<your GCP project id>
export TAG=<the new tag>

cd <your clone of key-share-holders>
git fetch --tags && git checkout "$TAG"
git describe --tags --exact-match   # expect: the NEW tag
git status --porcelain              # expect: no output

cd partner
# init again. A release may add a provider, and plan fails until you do.
# It is safe to run at any time and changes no infrastructure.
terraform init -reconfigure -input=false \
  -backend-config="bucket=$PROJECT-tfstate" \
  -backend-config="prefix=cofhe-tdx-keygen/partner"

terraform plan  -var-file=../values.tfvars -var partner_project_id=$PROJECT
terraform apply -var-file=../values.tfvars -var partner_project_id=$PROJECT
```

**What to expect.** Each reader gate lists 1 or 2 image digests. Each digest has its own
read binding, keyed `<reader>@<digest>`. A new consumer image is added next to the old
one, and the old one is removed in a later release. So the running consumers keep their
read access during the whole upgrade.

Per changed row in `EXPECTED.md`:

| What changed | What the plan shows |
|---|---|
| a consumer digest **ADDED** (teecryptor, zee-k) | 1 change (its gate lists the new digest) + 1 add (its read binding) |
| a consumer digest **REMOVED** | 1 change (its gate drops the digest) + 1 destroy (its read binding) |
| the keygen image | 2 changes (the write gate and the `keygen-reader` gate), plus the replacements below |
| a ceremony window opening | 4 adds (`attested_add` and `keygen_version_viewer`, on each secret) |
| a ceremony window closing | 4 destroys (the same four bindings), nothing added |

A reader gate shows 1 change per release, however many of its rows move.

A new keygen digest also replaces bindings. The `attested_add`,
`keygen_version_viewer` and `reshare_read` bindings name the keygen digest, and a member string cannot be edited.
So expect 1 destroy and 1 add for each of them that exists: the first two while write
access is granted, `reshare_read` with `grant_reshare_read=true`.

For the three-image example above, expect **2 to add, 4 to change, 0 to destroy**. Match
the plan against the **CHANGED**, **ADDED** and **REMOVED** rows in `EXPECTED.md`. A
resource that no row explains is still a reason to stop and send us the plan.

Your plan also proves each new digest against its commit before it pins anything. That
needs `gh` on this machine, as in [step 1](#1-prerequisites). If we ever add a tool, the
release notes say so.

Then run the `verify/` check from [step 6](#6-apply-then-verify) again, including its
`init` line, and send us the output.

### Tags A and B: an upgrade in two releases

An upgrade of a consumer image, and a reshare, use two release tags of this repository:

Every consumer upgrade uses tags A and B: partners pin exact digests, so a one-release
swap leaves a window where old or new consumers cannot read. A low-risk upgrade may use
one release with `keep_previous_readers=false` and accept a short restart window.

1. **Tag A** keeps the previous image next to the new one. Each changed reader lists 2
   images: the new one, and the previous one, marked *previous* in `EXPECTED.md`. Old
   and new consumers can both read. The plan adds bindings and changes gates. It
   destroys no read binding, unless the reader already listed 2 images: then the newer
   of the two goes, and the older one stays, because it still runs.
2. Fhenix deploys the new consumers and confirms that they work.
3. **Tag B** removes the previous images. Each reader lists 1 image again. The plan
   changes each gate and destroys the read binding of each previous image.

A reader never lists more than 2 images. A release that keeps previous images and does
not move a reader keeps that reader's list, so an unrelated release does not end an
upgrade. Apply tag B after a successful roll, before any new upgrade. In a reshare, you
apply tag A with the reshare flags and tag B without them. See
[A reshare](RESHARE.md).

### The first release with image lists (one time)

<!-- FIRST-LIST-RELEASE -->
Remove this section after every partner applies it.

If you are not on the previous release, apply it first. Then apply the first list release.

The first release with image lists changes how Terraform tracks your read bindings. The
old resource `attested_read` held one binding per reader. The new resource
`attested_read_image` holds one binding per reader image. The release tells Terraform to
forget the old bindings, without a destroy. Then it adds the same members again under
the new name. Your live read access does not stop at any time.

The plan of that first release shows:

```
  # module.onboarding.google_iam_workload_identity_pool_provider.reader["keygen"] will be created
  +   disabled = true
  # module.onboarding.google_iam_workload_identity_pool_provider.reader["teecryptor"] will be updated in-place
  -   && attribute.image_digest == "sha256:…"
  +   && attribute.image_digest in ["sha256:…"]
  # module.onboarding.google_secret_manager_secret_iam_member.attested_read["teecryptor"] will no longer be managed by Terraform, but will not be destroyed
  # module.onboarding.google_secret_manager_secret_iam_member.attested_read_image["teecryptor@sha256:…"] will be created
  …
Plan: 3 to add, 2 to change, 0 to destroy.

Warning: Some objects will no longer be managed by Terraform
```

- **3 to add:** one `attested_read_image` binding per reader, and the `keygen-reader`
  gate. Each binding has the same member as the binding Terraform forgets. The gate is
  disabled: it opens only for a reshare.
- **2 to change:** the `teecryptor-reader` and `zee-k-reader` gates. The CEL changes from
  `==` to `in [...]`. The digest stays the same.
- **0 to destroy.** A destroy here is a reason to stop and send us the plan.
- **"will no longer be managed" and the warning** are expected, once per reader. The old
  bindings stay live, and the new resource now holds the same members.

If the same release also moves an image, its rows in `EXPECTED.md` add their adds and
destroys. Its gate change is one of the 2. If your project already has the
`keygen-reader` gate, it shows as 1 change, not 1 add.

**Apply that first release with read access on.** Do not pass `grant_read_access=false`
in the same apply. Terraform forgets the old bindings and does not remove them. So with
the brake on in that apply, the old members stay live, and no Terraform state holds them.
If you need the brake, apply the release first, then apply the brake in a second,
separate apply.
If you cannot apply the release now, apply the brake with your installed release.

If you applied the brake in the same apply by mistake, the old binding stays live. Remove
it by hand, one call per secret and per old reader image:

```
gcloud secrets remove-iam-policy-binding <SECRET_ID> --project=<PARTNER_PROJECT_ID> \
  --role=roles/secretmanager.secretAccessor \
  --member="principalSet://iam.googleapis.com/projects/<PARTNER_PROJECT_NUMBER>/locations/global/workloadIdentityPools/cofhe-tee-reader-pool/attribute.image_digest/<OLD_IMAGE_DIGEST>"
```

---

## Apply a later release while write access is granted

Use this section when a release arrives between [step 8](#8-grant-write-access) and
[step 11](#11-revoke-write-access). Your write access is granted, and the ceremony has not
run yet. The steps are the same as in [Apply a later release](#apply-a-later-release), with
one difference: `plan`, `apply` and `verify/` keep every flag from your tag A apply.
That is `-var grant_write_access=true`, and also `-var grant_reshare_read=true` if you
set it for a reshare. Without `grant_write_access`, the apply removes your write
bindings, and the keygen cannot write your share. Without `grant_reshare_read`, the
apply closes the keygen read, and the reshare fails.

```bash
# Your GCP project ID, the same one you used in onboarding. Not the project number.
export PROJECT=<your GCP project id>
export TAG=<the new tag>

cd <your clone of key-share-holders>
git fetch --tags && git checkout "$TAG"
git describe --tags --exact-match   # expect: the NEW tag
git status --porcelain              # expect: no output

cd partner
terraform init -reconfigure -input=false \
  -backend-config="bucket=$PROJECT-tfstate" \
  -backend-config="prefix=cofhe-tdx-keygen/partner"

terraform plan  -var-file=../values.tfvars -var partner_project_id=$PROJECT \
  -var grant_write_access=true
terraform apply -var-file=../values.tfvars -var partner_project_id=$PROJECT \
  -var grant_write_access=true

terraform -chdir=verify init -backend=false -input=false
terraform -chdir=verify plan -input=false \
  -var-file=../../values.tfvars -var partner_project_id=$PROJECT \
  -var grant_write_access=true
# In a reshare, add -var grant_reshare_read=true to all three commands.
```

**What to expect.** The per-pin table in
[Apply a later release](#apply-a-later-release) applies, with the keygen row for an open
window. When all three images change:

| | Plan |
|---|---|
| With `-var grant_write_access=true` (correct) | **6 to add, 4 to change, 4 to destroy** |
| Without it (the window closes) | 2 to add, 4 to change, 4 to destroy |

The four destroys are normal. The `attested_add` and `keygen_version_viewer` bindings
name the keygen digest. So each one is replaced for the new keygen digest. The two other adds
are the read bindings of the new consumer digests. If your plan shows 2 to add, stop.
The flag is missing. Do not apply.

`verify/` must show a `SUCCESS` block with `write_access_granted = true`. Send us the
output.

Do not run [step 11](#11-revoke-write-access) now. We ask for it after the ceremony.

---

## A reshare (only when Fhenix asks)

See [RESHARE.md](RESHARE.md).

## Things you must never do

- **Never** make an `image_digest` empty. This removes the pin from the gate.
- **Never** remove an image from a reader's `images` list by hand, or add one. The
  release decides the list. A removed image locks out the consumers that still run it.
- **Never** apply from `main`. See [Apply a later release](#apply-a-later-release).
- **Never** edit a `source_sha` to make a failing check pass. A failure means the digest
  and the commit do not belong together. Send it to us.
- **Never** give `secretAccessor` on a share to a person or to a service account.
- **Never** delete a secret. Each secret has `prevent_destroy`. For secret versions,
  see *Keep your old secret versions* in [RESHARE.md](RESHARE.md).
- **Never** apply a configuration file that did not arrive through the agreed channel.
  Ask us first. The digest is the security boundary.
- `grant_read_access = false` is your **emergency brake**. It removes your share from
  the read set. The network continues while enough partners remain. Use it with care,
  and tell us. From your clone, in `partner/`:
  ```bash
  terraform apply -var-file=../values.tfvars -var partner_project_id=$PROJECT \
    -var grant_read_access=false
  ```
  The provenance check still runs on a revoke. If a host in the table in step 1 is
  unreachable, add `skip_provenance_check`:
  ```bash
  terraform apply -var-file=../values.tfvars -var partner_project_id=$PROJECT \
    -var grant_read_access=false -var skip_provenance_check=true
  ```
  Use this flag only when a check blocks an urgent revoke. Terraform refuses it on any
  apply that grants read or write access.

  **That apply still writes the tag's digests into your gates, and it proves none of
  them.** No binding accompanies them, so nothing can read your share. Re-apply without
  the flag when the hosts are reachable again. That proves the digests.

  That lasts one command. The next apply without it restores read access. To keep it off,
  set `grant_read_access = false` in your own `partner/terraform.tfvars`.
  While the brake is on, run `verify/` with `-var grant_read_access=false`. It then
  expects no reader binding on each secret.

## Ongoing commitment

| When | What you do | Effort |
|---|---|---|
| Onboarding | This page, one time | 1 to 2 hours |
| Directly after the ceremony | Revoke write access ([step 11](#11-revoke-write-access)) | 5 minutes |
| A reshare, only when we ask | Apply tag A with the flags, then tag B without them. See [A reshare](RESHARE.md). | 2 × 5 minutes |
| Each Fhenix release | Check out the new tag and apply. See [Apply a later release](#apply-a-later-release). | 5 minutes |
| Always | Keep the project and Secret Manager available. Google manages both. No on-call. | none |

## Reference

### What the provenance gate checks

A digest says **which** image runs. It cannot say who built it: the attestation token
carries no repository or commit claim, so your CEL cannot hold that proof. The gate holds
it instead, one step earlier.

It runs on every `plan` and every `apply`, in `partner/`, once per pinned image. A reader
with 2 images is checked twice, once per digest:

- A SLSA build provenance attestation exists for that exact digest.
- That exact workflow file produced it, on `refs/heads/main`, in our repository. The
  check matches the whole identity, so another workflow in the same repository fails.
- It was built from the exact commit in `source_sha`.

A failure stops the run before any IAM changes. The check is a data source, so `-target`
does not route around it.

It does not say the commit is one you approve of. You choose which of our commits you
trust, from our public history.

The check reads each image from our public registry. So **we never delete a pinned
image**. The registry repositories have no cleanup policy. If a pinned image is ever
missing, your plan stops with `COULD NOT CHECK`. Do not remove the digest to make the
plan pass. Send us the error.

### Why we do not ask for more

The Terraform in `partner/` needs `secretmanager.secrets.setIamPolicy`. It sets IAM on each
secret; that is its job. A holder of this permission can give read access on a secret to
itself, then read it. Two partner shares are sufficient to reconstruct the key.

So we do not hold this permission, at any time. **You run the applies.** We considered a
different option: hold the permission only during onboarding, while your secrets are
empty. We rejected it. A permission given outside Terraform in that window remains after
the window closes. It becomes active when your share is written.

The ceremony does not need this permission. Our enclave identifies itself to your CEL
with hardware attestation, not with the credentials of a Fhenix employee.

### What `verify/` checks

- The write gate pins the keygen image digest, the Fhenix compute project, and genuine
  Intel TDX Confidential Space.
- Each read gate pins every listed image digest and the compute project of its
  consumer. It requires debugging disabled since boot.
- Each identity on each secret is an attested `principalSet`. There is no `user:` and
  no `serviceAccount:`.
- Each secret has one reader binding. Its members are the listed images of the consumer
  that owns the secret, and the keygen image only while `grant_reshare_read = true`.
- The write binding exists only while `grant_write_access = true`.
- The `secretmanager.viewer` binding of the keygen exists only while
  `grant_write_access = true`. The keygen write principal is its only member.

> **What the gates say.** Each CEL requires genuine **Intel TDX Confidential Space**
> hardware and software, the **STABLE** image tier (debug and experimental images are
> rejected), a request from our compute project, and the exact image digest (a read gate
> accepts each digest in its list, at most 2). The read
> gates also require **debugging disabled since boot**. If one condition fails,
> access is refused. There is no partial access and no fallback.

### Audit logs

The module turns on Secret Manager **Data Access audit logs** in your project. Google
leaves these logs off by default. Off means that a read of your share leaves no
record. On means that each read is logged with the identity that made it. You can
check at any time that only the attested consumer principals read your share:

```bash
gcloud logging read \
  'protoPayload.methodName="google.cloud.secretmanager.v1.SecretManagerService.AccessSecretVersion"' \
  --project=$PROJECT --freshness=30d \
  --format='value(timestamp,protoPayload.authenticationInfo.principalSubject)'
# expect only principal://…/workloadIdentityPools/cofhe-tee-reader-pool/… subjects
```

### Check a digest yourself

Optional. Your `plan` and `apply` already run this check, and stop if a digest did not
come from the commit beside it. To run it on its own:

```bash
./partner/verify-image.sh keygen "<image_digest>" "<source_sha>"   # also teecryptor, zee-k
```

`FAIL` means: change nothing, send us the output.

That reads our copy of the attestation, which ships in the tag. To fetch the same
attestation from GitHub instead:

```bash
FHENIX_IGNORE_SHIPPED_BUNDLE=1 ./partner/verify-image.sh keygen <digest> <commit>
```

Both check the same signature against the same public trust roots, so a pass means the
same thing. Only the source of the file changes.

The second form calls `api.github.com`. A `COULD NOT CHECK … HTTP 403` means GitHub limits
requests from your address: the anonymous limit is 60 an hour for each IP, shared by
everyone behind it. Wait and run it again, or pass any GitHub token to raise the limit:

```bash
FHENIX_PROVENANCE_TOKEN=<token> ./partner/verify-image.sh …
```

A token is never required, and it changes nothing about what is proven.

### The same checks by hand

If you prefer not to use `verify/`, these `gcloud` commands do the same checks. Put
the digests from `EXPECTED.md` at the tag into the first lines. A reader with 2 images
lists both, in the order of `EXPECTED.md`, separated by `, `. Each `check` compares the
whole digest condition, so a missing, an extra or a reordered digest is a `FAIL`. The
script prints `OK` or `FAIL` for each gate. You do not compare anything by eye.

```bash
PROJ=$PROJECT
KEYGEN_DIGEST=sha256:…                 # from EXPECTED.md at the tag
TC_DIGESTS='"sha256:…", "sha256:…"'    # one or two, quoted, in EXPECTED.md order
ZK_DIGESTS='"sha256:…"'

check() {   # provider, pool, expected digest condition
  cel=$(gcloud iam workload-identity-pools providers describe "$1" \
        --location=global --workload-identity-pool="$2" \
        --project="$PROJ" --format='value(attributeCondition)')
  case "$cel" in
    *"$3"*) echo "OK    $1 has $3" ;;
    *)      echo "FAIL  $1 does NOT have $3" ;;
  esac
}
check cofhe-tee-keygen-provider cofhe-tee-keygen-pool "attribute.image_digest == \"$KEYGEN_DIGEST\""
check teecryptor-reader         cofhe-tee-reader-pool "attribute.image_digest in [$TC_DIGESTS]"
check zee-k-reader              cofhe-tee-reader-pool "attribute.image_digest in [$ZK_DIGESTS]"
check keygen-reader             cofhe-tee-reader-pool "attribute.image_digest in [\"$KEYGEN_DIGEST\"]"

# expect: True. The keygen read gate is disabled outside a reshare.
gcloud iam workload-identity-pools providers describe keygen-reader \
  --location=global --workload-identity-pool=cofhe-tee-reader-pool \
  --project="$PROJ" --format='value(disabled)'

for s in cofhe-tee-fhe-priv cofhe-tee-zk-signer; do
  echo "== $s =="
  gcloud secrets get-iam-policy "$s" --project="$PROJ" \
    --format='table(bindings.role,bindings.members)'
done
```

Expect one `OK` line per `check`. In the IAM tables, expect one `secretAccessor` for
each secret, with one member per reader image. Between steps 8 and 11, also expect one
`secretVersionAdder` and one `secretmanager.viewer`. All must point to a
`principalSet://…/attribute.image_digest/sha256:…`. There must be no `user:` and no
`serviceAccount:`. If you see a `FAIL`, a person, or a service account: stop and
contact us.
