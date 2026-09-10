# partner-onboarding (Terraform module)

This module is the **complete** partner side of CoFHE TEE key creation. A partner
applies it one time. The apply gives our attested keygen enclave permission to write a
key share into the partner's Secret Manager. A CEL on our attestation gates that write.
**There is no service and no binary on the partner side. Onboarding is
`terraform apply`.**

## What it provisions

| Resource | Purpose |
|----------|---------|
| `google_secret_manager_secret` (×N) | Receives the key share as new versions. |
| `google_iam_workload_identity_pool` + `_provider` (write) | OIDC trust for the Confidential Space token of the keygen enclave. |
| `google_iam_workload_identity_pool` `cofhe-tee-reader-pool` + one `_provider` per consumer | OIDC trust for the token of each consumer enclave. |
| CEL `attribute_condition` on each provider | The gate. Only our genuine attested image, from our project, can get a token. |
| `google_project_iam_audit_config` (Secret Manager) | Data Access audit logs. Each read of a share is logged in the partner's project. |
| `google_secret_manager_secret_iam_member` | Gives `secretVersionAdder` (keygen) and `secretAccessor` (each consumer, on its own secret) **directly** to attested federated principals. No service account. |

The module does **not** create a bucket. Public material (ServerKey, CRS,
CompactPublicKey) is in *our* GCS bucket, not in the partner's project. The keygen
grant is `secretVersionAdder` (append only). It is never `secretAccessor`. The
enclave can add versions. It cannot read key material.

## Usage

```hcl
module "cofhe_keygen_onboarding" {
  source = "github.com/FhenixProtocol/key-share-holders//partner/modules/partner-onboarding?ref=<tag>"

  partner_project_id = "<your-project>"
  service_project_id = "fhenix-compute-project"   # Fhenix compute project. We provide this.

  # Pin the exact keygen image. Never leave this unset for a real partner.
  image_digest = "sha256:<keygen digest>"           # REQUIRED in production. We provide this.
}

output "onboarding" {
  value = {
    wip_audience       = module.cofhe_keygen_onboarding.wip_audience
    partner_project_id = module.cofhe_keygen_onboarding.partner_project_id
    secret_ids         = module.cofhe_keygen_onboarding.secret_ids
  }
}
```

## Inputs

The module has 11 input variables. [`variables.tf`](variables.tf) documents each
one — its type, default, and purpose. [`../../terraform.tfvars.example`](../../terraform.tfvars.example)
shows a filled-in example. The sections below explain the variables that carry a
safety decision: the image pin, attested reads, and write access.

## The return tuple

After the apply, the partner sends us the outputs: `wip_audience`,
`partner_project_id`, `secret_ids`. We register them. The keygen job uses
`wip_audience` to attest for this partner, and writes the share to `secret_ids`. With
`attested_readers` set, the partner also returns `reader_wip_audiences`
(consumer => audience). Each consumer enclave attests for its audience to read its
secret.

## Pinning the image (production workflow)

> **Production MUST pin.** With an empty `image_digest` (the development default), the
> CEL accepts *any* attested Confidential Space workload in our project. This is
> acceptable only for development. For a real partner, always set the digest.

The digest is **deployment input, not committed code**. Do not edit `variables.tf`.
Do not commit a digest. The flow for each release:

1. Fhenix builds a release and publishes a tag. Its `values.tfvars` at the root of
   this repository carries the digest, for example `sha256:1c64b906…`.
2. Check out the tag. You edit nothing.
3. Run `terraform apply -var-file=../values.tfvars -var partner_project_id=<your-project>`.
   This adds `&& attribute.image_digest == "sha256:..."` to the CEL. Only that exact
   image can then write to your Secret Manager.

The pinned value is in the **deployed CEL** (and in the Terraform state), not in the
repo. Read it at any time:

```bash
gcloud iam workload-identity-pools providers describe cofhe-tee-keygen-provider \
  --location=global --workload-identity-pool=cofhe-tee-keygen-pool \
  --project=<partner-project> --format='value(attributeCondition)'
```

## Attested read access (partner-enforced)

`attested_readers` is the only read path. The **partner's own** IAM gates each read on
the TDX Confidential Space attestation of the consumer. No service account is trusted.
One entry per consumer:

```hcl
attested_readers = {
  teecryptor = {
    gce_project_id = "fhenix-compute-project"  # the consumer's COMPUTE project
    image_digest   = "sha256:ab12..."            # the consumer's image. REQUIRED, always pinned.
    secret_id      = "cofhe-tee-fhe-priv"
  }
}
```

The module creates one reader pool (`cofhe-tee-reader-pool`) per partner, and one
provider per consumer (`<consumer>-reader`). The CEL of each provider requires genuine
`GCP_INTEL_TDX` Confidential Space, the `STABLE` support tier, and
`dbgstat == "disabled-since-boot"`. It pins the compute project and the exact image
digest of the **consumer**. The keygen image, or any other workload, cannot satisfy it.
The `secretAccessor` grant goes to the digest-scoped attested principal, on **only**
that consumer's secret. There is no unpinned fallback. A new consumer image needs a
partner re-apply with the new digest. This is explicit consent for each image, the same
as for the keygen write pin.

`grant_read_access = false` removes all attested read bindings. The pool, the
providers and the secrets stay. This is reversible.

## Write access is off by default (you stay in control)

Key creation is **bootstrap only**. So `grant_write_access` **defaults to `false`**:
at the start, our enclave cannot add a secret version. Write access is a deliberate
action for each ceremony:

```hcl
grant_write_access = true    # ONLY for the apply before a key ceremony
```

After the ceremony, remove the line (or apply again without it). This removes the
`secretVersionAdder` binding. After that, a write attempt by our enclave fails with a
permission error. The error is visible in our logs and in your audit log. It is never a
silent success. The secret, its versions, and the pool and provider do not change. The
action is fully reversible.

> **Why the default is `false`.** The default was `true`. Then, if you forgot the flag
> on an unrelated re-apply (for example, a new consumer image digest), the apply gave
> write access again, silently. With the default `false`, the same mistake removes
> access instead. That is the safe direction, and `terraform plan` shows it as a
> destroy.

Check the current state at any time:

```bash
gcloud secrets get-iam-policy <secret-id> --project=<partner-project> \
  --format='value(bindings.role)' | grep secretVersionAdder || echo "REVOKED (no write binding)"
```

This is independent of the image pin. Removal of write access removes all write
access. The pin only limits *which* image can write while access exists.

## Verifying what landed: `partner/verify`

After the apply, the partner (or Fhenix, with the viewer roles) runs a second root. It
is **read-only** and uses the same var-file:

```bash
terraform -chdir=verify init -backend=false -input=false
terraform -chdir=verify plan -input=false \
  -var-file=../../values.tfvars -var partner_project_id=<your-project>
```

`verify/` has no `resource` blocks. Its data sources read the live write CEL, the live
read CELs, and the IAM policy of each secret. Its `postcondition`s check:

- each gate pins the expected digest, the compute project, and TDX Confidential Space
  (the read gates also `dbgstat`);
- each member on a share is an attested `principalSet`. There is no `user:` and no
  `serviceAccount:`;
- each secret has exactly one `secretAccessor`, and it is the digest-scoped consumer
  for that secret;
- the `secretVersionAdder` binding is present if, and only if,
  `grant_write_access = true`.

Success prints a `SUCCESS` output block. A failure is a hard error. Each error ends
with a `CHECK FAILED:` line in plain language, with the unexpected value. This replaces
the manual gcloud checks. It found out-of-band `secretAccessor` grants on the staging
partners that Terraform state could not see.

## Audit logging

The module turns on Secret Manager **Data Access** audit logs (`DATA_READ` and
`ADMIN_READ`) in the partner project. Google leaves these logs off by default. Off
means that a `secretmanager.versions.access` call, the actual read of a share, leaves no
record. On means that each read shows who made it:

```bash
gcloud logging read \
  'protoPayload.methodName="google.cloud.secretmanager.v1.SecretManagerService.AccessSecretVersion"' \
  --project=<partner-project> --freshness=30d \
  --format='value(timestamp,protoPayload.authenticationInfo.principalSubject)'
```

Expect only `principal://…/workloadIdentityPools/cofhe-tee-reader-pool/…` subjects, at
consumer boot times. A `user:` or a `serviceAccount:` here is a read outside the
attestation gate. Investigate it. The setting applies to Secret Manager only. The audit
config of other services in the project does not change.

## Image rotation

- **Not pinned (`image_digest = ""`):** no partner action when we rebuild. Development
  only.
- **Pinned:** a new image has a new digest. The partner applies again with the new
  `image_digest`. This is the point: explicit consent for each image. For a rollover
  with no gap, pin a list for a short time (old and new), deploy, then remove the old
  one. (The module takes one digest today. Multi-digest rollover is a future
  enhancement.)
