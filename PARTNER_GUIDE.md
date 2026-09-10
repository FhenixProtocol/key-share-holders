  # Partner Dev — Initializationֿ

You put the configuration file that we send you
into it. You apply. This creates two Secret Manager entries and the IAM rules that
decide **which attested Fhenix enclave can write your key share, and which can read
it**.

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
> read access on a share to itself. We do not take it. See step 3.

## 1. Prerequisites

Make sure you followed PROJECT_CREATION.md and filled the form at https://forms.gle/8XjawvVSWZSGCg45A

- `terraform` 1.9 or later, and `gcloud`.

## 2. Create your Terraform state bucket

```bash
gcloud storage buckets create gs://<your-project>-tfstate \
  --project=<your-project> --uniform-bucket-level-access
```

## 3. Give Fhenix read-only access

With this access, we can check your configuration without a request to you. This
applies to onboarding and to each release after it.

First get the repository and check out the tag we sent you. Everything from here on
runs from inside that clone.

```bash
git clone https://github.com/FhenixProtocol/key-share-holders
cd key-share-holders
git fetch --tags && git checkout <tag>
```

Then apply the read-only grant:

```bash
cd access
terraform init -reconfigure -input=false \
  -backend-config="bucket=<your-project>-tfstate" \
  -backend-config="prefix=cofhe-tdx-keygen/access" \
  && terraform apply -var="partner_project_id=<your-project>"
# `operators` defaults to ["group:protocol@fhenix.io"]
```

`-input=false` makes `init` fail instead of asking *"Do you want to migrate all
workspaces to gcs?"*. That question must not appear on a new setup; answering it
wrongly overwrites state. The `&&` stops `apply` from running after a failed `init`.

This binds two **Google-predefined** roles to our operator group in your project:

| Role | What it permits | What it does not permit |
|---|---|---|
| `roles/secretmanager.viewer` | See that a version exists, and when. This shows us that a ceremony completed. | Read the value (`versions.access`). Change IAM. |
| `roles/iam.workloadIdentityPoolViewer` | Read your deployed CEL. This shows us the digest pin. | Change anything. |

**These are Google roles, not roles that we made.** Check them in the Google
documentation. Do not accept our description of them. Both roles apply to this project
only. `-var grant_view_access=false` removes them at any time.

> **Why we do not ask for more.** The Terraform in step 5 needs
> `secretmanager.secrets.setIamPolicy`. It sets IAM on each secret; that is its job.
> A holder of this permission can give read access on a secret to itself, then read it.
> Two partner shares are sufficient to reconstruct the key.
>
> So we do not hold this permission, at any time. **You run the applies.** We
> considered a different option: hold the permission only during onboarding, while
> your secrets are empty. We rejected it. A permission given outside Terraform in
> that window remains after the window closes. It becomes active when your share is
> written.
>
> The ceremony does not need this permission. Our enclave identifies itself to your
> CEL with hardware attestation, not with the credentials of a Fhenix employee.

Check what we hold, at any time:

```bash
gcloud projects get-iam-policy <your-project> \
  --flatten="bindings[].members" \
  --format="value(bindings.role,bindings.members)" | grep protocol@fhenix.io
# expect ONLY: roles/secretmanager.viewer
#              roles/iam.workloadIdentityPoolViewer
```

## 4. Check the release you got

You cloned the repository and checked out the tag in step 3. Now confirm it is what we
published. The GitHub Release for that tag carries the sha256
of its source tarball; the two must match:

```bash
curl -sL https://github.com/FhenixProtocol/key-share-holders/archive/refs/tags/<tag>.tar.gz \
  | shasum -a 256
```

Read `EXPECTED.md` at the root. It lists every value this release pins, and what your
plan and your `verify/` run must show. Read
`partner/modules/partner-onboarding/README.md` before you apply. This module *is* the
partner side. There is no binary and no service in this design.

`values.tfvars` at the root holds the shared values. You do not edit it. It has this
form:

```hcl
service_project_id = "fhenix-compute-project"

# Only this exact keygen image can WRITE your share.
image_digest = "sha256:…"

# Ceremony only. The module default is false (frozen). This line is in the
# values.tfvars of a ceremony release. It is absent in the release after it.
grant_write_access = true

# Only these exact consumer images can READ your share. Each reads ONE secret.
attested_readers = {
  teecryptor = { gce_project_id = "fhenix-compute-project", image_digest = "sha256:…", secret_id = "cofhe-tee-fhe-priv" }
  zee-k      = { gce_project_id = "fhenix-compute-project", image_digest = "sha256:…", secret_id = "cofhe-tee-zk-signer" }
}
```

Your own project id is **not** in that file, and is in no file. You pass it with
`-var partner_project_id=<your-project>` on every command below.

There is no other read path. Each read of your share goes through these gates. The
module has no input that gives read access to a person or to a service account.

> **Do not make an `image_digest` empty.** An empty digest means *not pinned*: any
> attested workload in our project can then write to your secrets. Terraform rejects a
> value that is not `sha256:` plus 64 lowercase hex characters. A cut-off paste fails
> with an error. It does not weaken the gate.

## 5. Init and plan

```bash
cd ../partner        # from access/, where step 3 left you
terraform init -reconfigure -input=false \
  -backend-config="bucket=<your-project>-tfstate" \
  -backend-config="prefix=cofhe-tdx-keygen/partner" \
  && terraform plan -var-file=../values.tfvars -var partner_project_id=<your-project>
```

**Correct result:** about fifteen resources to add. Zero to change. Zero to destroy.

```
Plan: 15 to add, 0 to change, 0 to destroy.

  # google_project_service.apis            -> secretmanager, iam, iamcredentials, sts, cloudresourcemanager
  # google_project_iam_audit_config.secretmanager   -> Data Access logs for Secret Manager
  # google_secret_manager_secret.bundle    -> "cofhe-tee-fhe-priv", "cofhe-tee-zk-signer"
  # google_iam_workload_identity_pool.pool          -> "cofhe-tee-keygen-pool"
  # google_iam_workload_identity_pool_provider      -> "cofhe-tee-keygen-provider"
  # google_iam_workload_identity_pool.reader_pool   -> "cofhe-tee-reader-pool"
  # google_iam_workload_identity_pool_provider.reader -> "teecryptor-reader", "zee-k-reader"
  # google_secret_manager_secret_iam_member.attested_add   -> secretVersionAdder  (x2)
  # google_secret_manager_secret_iam_member.attested_read  -> secretAccessor      (x2)
```

> **Stop and contact us** if you see one of these:
> - a *destroy* count that is not zero;
> - a `google_storage_bucket`;
> - a resource in a project that is not yours;
> - fewer than two secrets;
> - an `attested_read` binding on the wrong secret;
> - the question *"Do you want to migrate all workspaces to gcs?"* (answer **no**;
>   on a new setup this question must not appear).
>
> The resource count can differ by one or two. A **destroy** must not appear.

## 6. Apply, then verify

```bash
terraform apply -var-file=../values.tfvars -var partner_project_id=<your-project>

terraform -chdir=verify init -backend=false -input=false
terraform -chdir=verify plan -input=false \
  -var-file=../../values.tfvars -var partner_project_id=<your-project>
```

`verify/` is read-only. It has no resources. It reads the gates and the secret
permissions that are now live in your project. It compares them with the
`values.tfvars` of the tag you applied. (The list of checks is under *Reference*, at the end.)

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

The file has four values: your project id, the two secret ids, and the audiences that
our enclaves attest for. It has no secret material. We compare the project numbers in
it with the numbers compiled into our images. If they differ, the rollout stops on our
side, not on yours.

*(We cannot read your Terraform state. The viewer roles have no storage permissions.
You send this file; we do not fetch it.)*

## 8. Before the ceremony

Check that both secrets are empty. Then tell us that you are ready:

```bash
gcloud secrets versions list cofhe-tee-fhe-priv  --project=<your-project>
gcloud secrets versions list cofhe-tee-zk-signer --project=<your-project>
# expect: Listed 0 items.
```

## 9. During the ceremony

**Nothing to run.** Be available. If your project rejects the write, the ceremony
stops. This is by design. We may then ask you for your CEL string or your audit log.

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

One closing action: close the write window that the ceremony opened. Our write access
is for bootstrap only. **The module default is frozen** (`grant_write_access =
false`). The `values.tfvars` of the ceremony release sets it to `true` for that one
apply. We then publish a **post-ceremony tag** whose `values.tfvars` does not carry
that line. You check it out and apply. This removes the write binding.

```bash
# 1. take the post-ceremony tag
git fetch --tags && git checkout <post-ceremony-tag>
grep grant_write_access ../values.tfvars   # expect: no match

# 2. plan — expect EXACTLY 2 destroys, nothing else
terraform plan -var-file=../values.tfvars -var partner_project_id=<your-project>
#   Plan: 0 to add, 0 to change, 2 to destroy.
#   - google_secret_manager_secret_iam_member.attested_add["cofhe-tee-fhe-priv"]
#   - google_secret_manager_secret_iam_member.attested_add["cofhe-tee-zk-signer"]

# 3. apply
terraform apply -var-file=../values.tfvars -var partner_project_id=<your-project>

# 4. check that both secrets are frozen — same check as step 6, now with no write binding
terraform -chdir=verify plan -input=false \
  -var-file=../../values.tfvars -var partner_project_id=<your-project>
# success: a SUCCESS block with write_access_granted = false
# failure: "CHECK FAILED: the share … is still writable" — send it to Fhenix
```

> **Frozen is the default. If you forget this step, the result is safe.** If you apply
> again later for a different reason (for example, a new consumer digest) and the
> ceremony line is not there, write access stays removed. The old behaviour was the
> opposite: an absent flag gave write access again, silently. That is why we changed
> the default.

> If the plan in item 2 destroys anything other than the two `attested_add` bindings
> (for example, a **secret** or an `attested_read` binding), **do not apply**.
> Contact us.

This is reversible. A future key rotation ships as a new ceremony release, whose
`values.tfvars` carries the line again. Your read gates do not change. Decryption
continues to work.

## The End

---

## Things you must never do

- **Never** make an `image_digest` empty. This removes the pin from the gate.
- **Never** give `secretAccessor` on a share to a person or to a service account.
- **Never** delete a secret. Each secret has `prevent_destroy`. Removal of a secret is
  a deliberate, coordinated action.
- **Never** apply a configuration file that did not arrive through the agreed channel.
  Ask us first. The digest is the security boundary.
- `grant_read_access = false` is your **emergency brake**. It removes your share from
  the read set. The network continues while enough partners remain. Use it with
  care, and tell us.

## Ongoing commitment

| When | What you do | Effort |
|---|---|---|
| Onboarding | This page, one time | 1 to 2 hours |
| Directly after the ceremony | Freeze write access again (step 11) | 5 minutes |
| Each Fhenix release | Put the new tfvars in place and apply. See *Partner Dev — Image Upgrade*. | 5 minutes |
| Always | Keep the project and Secret Manager available. Google manages both. No on-call. | — |

## Reference

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

### The same checks by hand

If you prefer not to use `verify/`, these `gcloud` commands do the same checks. Put
the three digests from your expected-values sheet into the first three lines. The
script prints `OK` or `FAIL` for each gate. You do not compare anything by eye.

```bash
PROJ=<your-project>
KEYGEN_DIGEST=sha256:…      # from the expected-values sheet
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
