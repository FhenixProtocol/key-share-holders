# Partner Dev — Initialization

You check out the release tag we send you. It already carries the configuration file.
You apply. This creates two Secret Manager entries and the IAM rules that decide
**which attested Fhenix enclave can write your key share, and which can read it**.

**Time: 1 to 2 hours, one time.** After this, nothing runs on your side. We are on the
call with you.

> **We send you one thing: a release tag in this repository.**
> The tag carries everything — the Terraform, this guide, the `values.tfvars` with
> every shared value already filled in, and the `EXPECTED.md` that lists the exact
> strings your checks must show. Every partner gets the same tag.
>
> **You run each apply in your project. We cannot.** Fhenix has read-only access to
> your project. We check and we advise; you execute. This is by design. The Terraform
> that sets the IAM on your secrets needs one permission
> (`secretmanager.secrets.setIamPolicy`). The holder of that permission can give
> read access on a share to itself. We do not take it. See step 4.

## 1. Prerequisites

Make sure you followed PROJECT_CREATION.md and filled the form at https://forms.gle/8XjawvVSWZSGCg45A

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

You do not have to take our copy. *Check a digest yourself*, under **Reference**, fetches
the same attestation from GitHub instead. It is optional: your apply proves the images
either way.

## 2. Create your Terraform state bucket

```bash
gcloud storage buckets create gs://<your-project>-tfstate \
  --project=<your-project> --uniform-bucket-level-access
```

## 3. Get the release

We send you one thing: a release tag in this repository. Get it, and confirm it is what
we published. Everything from here on runs from inside this clone.

```bash
git clone https://github.com/FhenixProtocol/key-share-holders
cd key-share-holders
git fetch --tags && git checkout <tag>
```

Confirm you are on that tag, and that nothing is modified:

```bash
git describe --tags --exact-match   # expect: the tag we sent you
git status --porcelain              # expect: no output
```

The GitHub Release page for the tag also carries the sha256 of its source tarball. You
may compare it:

```bash
curl -sL https://github.com/FhenixProtocol/key-share-holders/archive/refs/tags/<tag>.tar.gz \
  | shasum -a 256
```

The two commands above check what you will apply. This one checks what we published.

### What the release carries

Four things, at the root of the clone:

- **`EXPECTED.md`** — every value this release pins, and what your `plan` and your
  `verify/` run must show. This is the file you check against.
- **`values.tfvars`** — the shared values themselves. You pass it with `-var-file`; you do
  not edit it, and the `git status --porcelain` above already proves it is byte-identical
  to what we tagged. Your own project id is **not** in it, and is in no file — you pass
  that with `-var partner_project_id=<your-project>` on every command below.
- **`partner/bundles/`** — one signed attestation for each pinned digest. Your apply reads
  them. You do not touch them. See `partner/bundles/README.md`.
- **`partner/modules/partner-onboarding/`** — the module itself. Read its README before you
  apply. This module *is* the partner side: there is no binary and no service in this
  design.

`values.tfvars` never grants write access. That is an apply-time flag, and it appears only
around a key ceremony. See steps 8 to 11.

### Where each image came from

`source_sha` is the commit each image was built from. Both `terraform plan` and
`terraform apply` check the SLSA build provenance of every digest against the public
Sigstore log, before anything is pinned. A digest that did not come from the commit beside
it fails, and nothing is written. You do not have to do anything for this to happen.

To run that check on its own, see *Check a digest yourself* under **Reference**.

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
> apply. See *Why we do not ask for more* under Reference.

```bash
cd access
terraform init -reconfigure -input=false \
  -backend-config="bucket=<your-project>-tfstate" \
  -backend-config="prefix=cofhe-tdx-keygen/access" \
  && terraform apply -var="partner_project_id=<your-project>"
# `operators` defaults to ["group:protocol@fhenix.io"]
```

Check what we hold, at any time:

```bash
gcloud projects get-iam-policy <your-project> \
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
  -backend-config="bucket=<your-project>-tfstate" \
  -backend-config="prefix=cofhe-tdx-keygen/partner" \
  && terraform plan -var-file=../values.tfvars -var partner_project_id=<your-project>
```

**Correct result:** 15 resources to add. Zero to change. Zero to destroy. Two more are
added if you apply with `-var grant_write_access=true`, which we ask for once, in step 8.

```
Plan: 15 to add, 0 to change, 0 to destroy.      # 17 with grant_write_access=true

  # google_project_service.apis            -> secretmanager, iam, iamcredentials, sts, cloudresourcemanager
  # google_project_iam_audit_config.secretmanager   -> Data Access logs for Secret Manager
  # google_secret_manager_secret.bundle    -> "cofhe-tee-fhe-priv", "cofhe-tee-zk-signer"
  # google_iam_workload_identity_pool.pool          -> "cofhe-tee-keygen-pool"
  # google_iam_workload_identity_pool_provider      -> "cofhe-tee-keygen-provider"
  # google_iam_workload_identity_pool.reader_pool   -> "cofhe-tee-reader-pool"
  # google_iam_workload_identity_pool_provider.reader -> "teecryptor-reader", "zee-k-reader"
  # google_secret_manager_secret_iam_member.attested_add   -> secretVersionAdder  (x2, only with grant_write_access=true)
  # google_secret_manager_secret_iam_member.attested_read  -> secretAccessor      (x2)

Changes to Outputs:
  + provenance_verified = { keygen = {...}, teecryptor = {...}, zee-k = {...} }
```

A passing provenance check prints nothing. That `provenance_verified` block is how you
know it ran, and it names the commit proven for each image.

> **Stop and contact us** if your plan shows one of these:
> - a *destroy* count that is not zero;
> - a `google_storage_bucket`;
> - a resource in a project that is not yours;
> - fewer than two secrets;
> - an `attested_read` binding on the wrong secret.
>
> On this first run a destroy must not appear: there is nothing yet to destroy. A later
> release may legitimately destroy a read binding when an image rotates. See
> *Apply a later release*.

### If something goes wrong

**`init` asks "Do you want to migrate all workspaces to gcs?"** — answer **no**. On a new
setup that question must not appear at all, and answering it wrongly overwrites state.
`-input=false` in the command above makes `init` fail instead of asking.

**`init` fails with `Failed to get existing workspaces: querying Cloud Storage failed`** —
your credentials expired. It is not a wrong bucket name. Run `gcloud auth
application-default login`. Those are separate from `gcloud auth login`.

**`plan` stops with `External Program Execution Failed` on `verify-image.sh`** — read the
last lines. The script says which of two things happened:

- **`FAIL`** — the proof does not hold. Change nothing. Do not edit a digest or a
  `source_sha` to make it pass. Send us the whole error.
- **`COULD NOT CHECK`** — the check did not finish. This says nothing about the image.
  A host in the table in step 1 was not reachable, or a file in `partner/bundles` is
  damaged. Correct that, then run the plan again.

Nothing is written in either case.

## 6. Apply, then verify

```bash
terraform apply -var-file=../values.tfvars -var partner_project_id=<your-project>

terraform -chdir=verify init -backend=false -input=false
terraform -chdir=verify plan -input=false \
  -var-file=../../values.tfvars -var partner_project_id=<your-project>
```

`verify/` is a separate Terraform root, so it needs its own `init`. Run that line every
time you come back to it, including in step 11. It holds no state, which is why
`-backend=false` is safe.

`verify/` is read-only. It has no resources. It reads the gates and the secret
permissions that are now live in your project. It compares them with the
`values.tfvars` of the tag you applied. (The list of checks is under *Reference*, at the end.)

**Run this every time, even after a successful apply.** Terraform sees only the bindings
it created. Any other binding on your secrets survives every apply, and `verify/` is the
only step that finds one.

**Success:** a `SUCCESS` block, and nothing else.

```
  + SUCCESS = {
      + partner_project      = "<your-project>"
      + write_gate_pins      = "sha256:…"
      + read_gates_pin       = { teecryptor = "sha256:…", zee-k = "sha256:…" }
      + write_access_granted = true
    }
```

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
terraform output -json > <your-project>-outputs.json
```

The file has five values: your project id, the two secret ids, the audiences that
our enclaves attest for, and the proven digest and commit of each image. It has no secret material. We compare the project numbers in
it with the numbers compiled into our images. If they differ, the rollout stops on our
side, not on yours.

*(We cannot read your Terraform state. The viewer roles have no storage permissions.
You send this file; we do not fetch it.)*

## 8. Open the write window

**Do this only when we ask.** We ask once, and the request names this step. It may arrive
together with the instruction that sent you here, or later. Nothing in this guide ever
asks for write access a second time.

First check that both secrets are still empty:

```bash
gcloud secrets versions list cofhe-tee-fhe-priv  --project=<your-project>
gcloud secrets versions list cofhe-tee-zk-signer --project=<your-project>
# expect: Listed 0 items.
```

If either is not empty, stop and tell us. Then open the window — one apply, one extra
flag:

```bash
terraform apply -var-file=../values.tfvars -var partner_project_id=<your-project> \
  -var grant_write_access=true
# Plan: 2 to add, 0 to change, 0 to destroy.   # the two secretVersionAdder bindings
```

Tell us when it is applied. Step 11 closes it again, and that is your last action.

> **This is the only flag we will ever ask you to pass.** A request for
> `grant_write_access=true` that did not come from us, or that arrives after the ceremony
> is done, is not legitimate. Stop and call us.

## 9. During the ceremony

**Nothing to run.** Be available. If your project rejects the write, the ceremony
stops. This is by design. We may then ask you for your CEL string or your audit log.

If you must use the emergency brake now, call us first. It stops the ceremony.

## 10. After the ceremony

**Nothing to do.** We see the result on our side. The run is all-or-nothing: it reports
completion only if each partner write was accepted. The final proof is our service: it
starts and reconstructs the key. We tell you when this is done.

If you want to see it yourself:

```bash
# exactly one ENABLED version, created in the ceremony window
gcloud secrets versions list cofhe-tee-fhe-priv --project=<your-project> --limit=1

# who wrote it
gcloud logging read \
  'protoPayload.methodName="google.cloud.secretmanager.v1.SecretManagerService.AddSecretVersion"' \
  --project=<your-project> --limit=5 \
  --format='value(protoPayload.authenticationInfo.principalSubject,timestamp)'
```

The writer is an attested federated principal from `cofhe-tee-keygen-pool`. It is
never a `user:` and never a `serviceAccount:`.

> **Do not give `secretAccessor` to yourself. Do not read the version value.** The
> share is useful only to the attested enclave. If you read it, you weaken the
> guarantee that you give. We never ask you for it.

## 11. Freeze write access again

One closing action: close the write window that the ceremony opened. Our write access is
for bootstrap only. **The module default is frozen** (`grant_write_access = false`), so
you close it by applying without the flag you used in step 8.

```bash
# 1. plan — expect EXACTLY 2 destroys, nothing else
terraform plan -var-file=../values.tfvars -var partner_project_id=<your-project>
#   Plan: 0 to add, 0 to change, 2 to destroy.
#   - google_secret_manager_secret_iam_member.attested_add["cofhe-tee-fhe-priv"]
#   - google_secret_manager_secret_iam_member.attested_add["cofhe-tee-zk-signer"]

# 2. apply
terraform apply -var-file=../values.tfvars -var partner_project_id=<your-project>

# 3. check that both secrets are frozen — same check as step 6, now with no write binding
terraform -chdir=verify plan -input=false \
  -var-file=../../values.tfvars -var partner_project_id=<your-project>
# success: a SUCCESS block with write_access_granted = false
# failure: "CHECK FAILED: the share … is still writable" — send it to Fhenix
```

> **Frozen is the default. If you forget this step, the result is safe.** The next apply
> you run for any other reason closes the window, because you will not pass the flag
> again. The old behaviour was the opposite: an absent flag gave write access back,
> silently. That is why we changed the default.

> If the plan in item 1 destroys anything other than the two `attested_add` bindings
> (for example, a **secret** or an `attested_read` binding), **do not apply**.
> Contact us.

This is reversible. A future key rotation asks you for the flag again. Your read gates do
not change. Decryption continues to work.

## The End

---

## Apply a later release

Onboarding happens once. After it, each Fhenix release is the same short loop. Everything
you need is in the tag. There is no other document.

**What a release looks like.** We build new images and publish a tag here. The tag carries
a new `values.tfvars` and a new `EXPECTED.md`. Some releases move one image; some move all
three. `EXPECTED.md` names exactly what moved. Here all three changed:

```
## What changes from v1.1.0

Changed: keygen, keygen-sha, teecryptor, teecryptor-sha, zee-k, zee-k-sha

| Pin | v1.1.0 | v1.2.0 | |
|---|---|---|---|
| Fhenix compute project | `fhenix-compute-project` | `fhenix-compute-project` | unchanged |
| keygen (write gate) | `sha256:1111…` | `sha256:aaaa…` | **CHANGED** |
| keygen source commit | `84028ad…` | `b71f004…` | **CHANGED** |
| teecryptor (read gate on cofhe-tee-fhe-priv) | `sha256:2222…` | `sha256:bbbb…` | **CHANGED** |
| teecryptor source commit | `9d20cf4…` | `c17ba39…` | **CHANGED** |
| zee-k (read gate on cofhe-tee-zk-signer) | `sha256:3333…` | `sha256:cccc…` | **CHANGED** |
| zee-k source commit | `397eca5…` | `e4d8812…` | **CHANGED** |
```

**What you run.** Five minutes, from your existing clone:

```bash
cd <your clone of key-share-holders>
git fetch --tags && git checkout <new-tag>
git status --porcelain              # expect: no output

cd partner
# init again. A release may add a provider, and plan fails until you do.
# It is safe to run at any time and changes no infrastructure.
terraform init -reconfigure -input=false \
  -backend-config="bucket=<your-project>-tfstate" \
  -backend-config="prefix=cofhe-tdx-keygen/partner"

terraform plan  -var-file=../values.tfvars -var partner_project_id=<your-project>
terraform apply -var-file=../values.tfvars -var partner_project_id=<your-project>
```

**What to expect. A rotation destroys bindings, and that is normal.** Each consumer's
read binding names its image digest inside the member string, and that string cannot be
edited. So a new consumer digest replaces the binding: one destroy and one add. The gate
itself is updated in place.

Per changed pin:

| What changed | What the plan shows |
|---|---|
| a consumer image (teecryptor, zee-k) | 1 change (its gate) + 1 destroy and 1 add (its read binding) |
| the keygen image | 1 change (the write gate). While a ceremony window is open, also 1 destroy and 1 add per secret: the write bindings embed the keygen digest too |
| a ceremony window opening | 2 adds (the write bindings) |
| a ceremony window closing | 2 destroys (the write bindings), nothing added |

For the three-image example above, expect **2 to add, 3 to change, 2 to destroy**. Match
the plan against the **CHANGED** rows in `EXPECTED.md`. A resource that no row explains is
still a reason to stop and send us the plan.

Your plan also proves each new digest against its commit before it pins anything. That
needs `gh` on this machine, as in step 1. If we ever add a tool, the
release notes say so.

Then run the `verify/` check from step 6 again, and send us the output.

---

## Things you must never do

- **Never** make an `image_digest` empty. This removes the pin from the gate.
- **Never** edit a `source_sha` to make a failing check pass. A failure means the digest
  and the commit do not belong together. Send it to us.
- **Never** give `secretAccessor` on a share to a person or to a service account.
- **Never** delete a secret. Each secret has `prevent_destroy`. Removal of a secret is
  a deliberate, coordinated action.
- **Never** apply a configuration file that did not arrive through the agreed channel.
  Ask us first. The digest is the security boundary.
- `grant_read_access = false` is your **emergency brake**. It removes your share from
  the read set. The network continues while enough partners remain. Use it with care,
  and tell us. From your clone, in `partner/`:
  ```bash
  terraform apply -var-file=../values.tfvars -var partner_project_id=<your-project> \
    -var grant_read_access=false
  ```
  The provenance check still runs on a revoke. If a host in the table in step 1 is
  unreachable, add `skip_provenance_check`:
  ```bash
  terraform apply -var-file=../values.tfvars -var partner_project_id=<your-project> \
    -var grant_read_access=false -var skip_provenance_check=true
  ```
  Use this flag only when a check blocks an urgent revoke. Terraform refuses it on any
  apply that grants read or write access.

  **That apply still writes the tag's digests into your gates, and it proves none of
  them.** No binding accompanies them, so nothing can read your share. Re-apply without
  the flag when the hosts are reachable again. That proves the digests.

  That lasts one command. The next apply without it restores read access. To keep it off,
  set `grant_read_access = false` in your own `partner/terraform.tfvars`.
  **`verify/` reports `CHECK FAILED … must have exactly one reader binding` while the
  brake is on.** That is the brake working: there is no reader binding left. It is the one
  case where that message is expected.

## Ongoing commitment

| When | What you do | Effort |
|---|---|---|
| Onboarding | This page, one time | 1 to 2 hours |
| Directly after the ceremony | Freeze write access again (step 11) | 5 minutes |
| Each Fhenix release | Check out the new tag and apply. See *Apply a later release* above. | 5 minutes |
| Always | Keep the project and Secret Manager available. Google manages both. No on-call. | — |

## Reference

### What the provenance gate checks

A digest says **which** image runs. It cannot say who built it: the attestation token
carries no repository or commit claim, so your CEL cannot hold that proof. The gate holds
it instead, one step earlier.

It runs on every `plan` and every `apply`, in `partner/`, once per pinned image:

- A SLSA build provenance attestation exists for that exact digest.
- That exact workflow file produced it, on `refs/heads/main`, in our repository. The
  check matches the whole identity, so another workflow in the same repository fails.
- It was built from the exact commit in `source_sha`.

A failure stops the run before any IAM changes. The check is a data source, so `-target`
does not route around it.

It does not say the commit is one you approve of. You choose which of our commits you
trust, from our public history.

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
- Each read gate pins the image digest and the compute project of its consumer. It
  requires debugging disabled since boot.
- Each identity on each secret is an attested `principalSet`. There is no `user:` and
  no `serviceAccount:`.
- Each secret has exactly one reader. The reader is the consumer that owns that secret.
- The write binding exists only while `grant_write_access = true`.

> **What the gates say.** Each CEL requires genuine **Intel TDX Confidential Space**
> hardware and software, the **STABLE** image tier (debug and experimental images are
> rejected), a request from our compute project, and the exact image digest. The two
> read gates also require **debugging disabled since boot**. If one condition fails,
> access is refused. There is no partial access and no fallback.

### Audit logs

The module turns on Secret Manager **Data Access audit logs** in your project. Google
leaves these logs off by default. Off means that a read of your share leaves no
record. On means that each read is logged with the identity that made it. You can
check at any time that only the attested consumer principals read your share:

```bash
gcloud logging read \
  'protoPayload.methodName="google.cloud.secretmanager.v1.SecretManagerService.AccessSecretVersion"' \
  --project=<your-project> --freshness=30d \
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
the three digests from `EXPECTED.md` at the tag into the first three lines. The
script prints `OK` or `FAIL` for each gate. You do not compare anything by eye.

```bash
PROJ=<your-project>
KEYGEN_DIGEST=sha256:…      # from EXPECTED.md at the tag
TC_DIGEST=sha256:…
ZK_DIGEST=sha256:…

check() {   # provider, pool, expected digest
  cel=$(gcloud iam workload-identity-pools providers describe "$1" \
        --location=global --workload-identity-pool="$2" \
        --project="$PROJ" --format='value(attributeCondition)')
  case "$cel" in
    *"$3"*) echo "OK    $1 pins $3" ;;
    *)      echo "FAIL  $1 does NOT pin $3" ;;
  esac
}
check cofhe-tee-keygen-provider cofhe-tee-keygen-pool "$KEYGEN_DIGEST"
check teecryptor-reader         cofhe-tee-reader-pool "$TC_DIGEST"
check zee-k-reader              cofhe-tee-reader-pool "$ZK_DIGEST"

for s in cofhe-tee-fhe-priv cofhe-tee-zk-signer; do
  echo "== $s =="
  gcloud secrets get-iam-policy "$s" --project="$PROJ" \
    --format='table(bindings.role,bindings.members)'
done
```

Expect three `OK` lines. In the IAM tables, expect exactly one `secretVersionAdder`
and one `secretAccessor` for each secret. Both must point to a
`principalSet://…/attribute.image_digest/sha256:…`. There must be no `user:` and no
`serviceAccount:`. If you see a `FAIL`, a person, or a service account: stop and
contact us.
