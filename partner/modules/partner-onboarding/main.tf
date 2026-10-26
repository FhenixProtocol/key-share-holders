terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.0" }
  }
}

# Partner onboarding module.
#
# This is the ENTIRE partner-side setup: a partner runs `terraform apply` with
# this module once to grant our attested keygen enclave the ability to write a
# key share into their Secret Manager, gated by a CEL on our attestation. There
# is no service, daemon, or binary on the partner side; onboarding == apply.
#
# Direct federated grant: the grant goes DIRECTLY to the attested federated principal
# (principalSet scoped by gce_project_id). There is no intermediate writer
# service account to impersonate. The CEL (attribute_condition) is the gate.
#
# Public material (ServerKey/CRS/CPK) is NOT handled here. It lives in OUR GCS
# bucket, not the partner's; partners only receive their secret share.

locals {
  # Always-on gates: genuine Intel TDX Confidential Space image, STABLE support
  # tier, attestation originating from our service project.
  base_conditions = [
    "attribute.hwmodel == \"GCP_INTEL_TDX\"",
    "attribute.swname == \"CONFIDENTIAL_SPACE\"",
    "(\",\" + attribute.support_attributes + \",\").contains(\",${var.required_support_attribute},\")",
    "attribute.gce_project_id == \"${var.service_project_id}\"",
  ]

  # Optional exact-image pin. Empty image_digest => not pinned (early dev);
  # a non-empty value appends `&& attribute.image_digest == "sha256:..."`.
  image_conditions = var.image_digest == "" ? [] : ["attribute.image_digest == \"${var.image_digest}\""]

  attribute_condition = join("\n&& ", concat(local.base_conditions, local.image_conditions))

  # Principal the write grant targets. In a SHARED compute project (keygen and the
  # reader enclaves co-resident, the production topology), scoping by
  # gce_project_id alone would let ANY attested workload in the project (including
  # a reader) mint a secretVersionAdder token. So when an image is pinned we scope
  # the write to that exact keygen image_digest; the unpinned dev default
  # (dedicated keygen project) falls back to project scoping. Production therefore
  # MUST pin image_digest (the CEL pins it too, defense in depth).
  write_principal = var.image_digest == "" ? (
    "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.pool.name}/attribute.gce_project_id/${var.service_project_id}"
    ) : (
    "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.pool.name}/attribute.image_digest/${var.image_digest}"
  )
}

resource "google_project_service" "apis" {
  for_each = toset([
    "secretmanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "cloudresourcemanager.googleapis.com",
  ])
  project            = var.partner_project_id
  service            = each.key
  disable_on_destroy = false
}

# Data Access audit logs for Secret Manager. Without this, AccessSecretVersion (a
# DATA_READ) is not logged at all, so a read of a share leaves no trace in the
# partner's project. With it, every read is attributable: the attested consumer
# principal on a legitimate read, or a human / service account on an illegitimate
# one. Authoritative for this one service only; other services' audit config is
# untouched. Volume is negligible: shares are read at consumer boot.
resource "google_project_iam_audit_config" "secretmanager" {
  project = var.partner_project_id
  service = "secretmanager.googleapis.com"
  audit_log_config {
    log_type = "DATA_READ"
  }
  audit_log_config {
    log_type = "ADMIN_READ"
  }
  depends_on = [google_project_service.apis]
}

# Secret(s) that receive the generated key share as new versions.
resource "google_secret_manager_secret" "bundle" {
  for_each  = toset(var.secret_ids)
  project   = var.partner_project_id
  secret_id = each.key
  replication {
    auto {}
  }
  # This secret is the partner's root-of-trust container; never let a config
  # change (e.g. a renamed or dropped secret_id) destroy and recreate it.
  # Removing the secret is a deliberate, manual act.
  lifecycle {
    prevent_destroy = true
  }
  depends_on = [google_project_service.apis]
}

# --- Workload Identity Pool + Provider (gates our service's attestation) ---
resource "google_iam_workload_identity_pool" "pool" {
  project                   = var.partner_project_id
  workload_identity_pool_id = var.pool_id
  depends_on                = [google_project_service.apis]
}

resource "google_iam_workload_identity_pool_provider" "provider" {
  project                            = var.partner_project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.pool.workload_identity_pool_id
  workload_identity_pool_provider_id = var.provider_id

  oidc {
    issuer_uri        = var.issuer_uri
    allowed_audiences = ["//iam.googleapis.com/${google_iam_workload_identity_pool.pool.name}/providers/${var.provider_id}"]
  }

  attribute_mapping = {
    "google.subject"               = "assertion.sub"
    "attribute.image_digest"       = "assertion.submods.container.image_digest"
    "attribute.hwmodel"            = "assertion.hwmodel"
    "attribute.swname"             = "assertion.swname"
    "attribute.support_attributes" = "assertion.submods.confidential_space.support_attributes.join(',')"
    "attribute.gce_project_id"     = "assertion.submods.gce.project_id"
  }

  attribute_condition = local.attribute_condition
}

# Grant secretVersionAdder DIRECTLY to the attested federated
# principal, scoped to the exact keygen image_digest when pinned (see
# local.write_principal: required so a co-resident reader enclave can't mint a
# write token in a shared compute project), else to gce_project_id (dev).
# secretVersionAdder appends new versions only, NOT secretAccessor: the enclave
# cannot read existing key material. No service account is involved.
#
# Revocation (var.grant_write_access = false): the partner removes this binding and
# the secretmanager.viewer version list (keygen_version_viewer), so our attested
# enclave can no longer add a secret version. The keygen write is for a ceremony or a reshare
# only. Once the partner has the key, they revoke and the secret is frozen; any
# later write attempt by us fails (and is visible/auditable, never silent). The
# pool/provider and the secret itself are untouched, so it is fully reversible
# (set back to true and re-apply to re-grant).
resource "google_secret_manager_secret_iam_member" "attested_add" {
  for_each  = var.grant_write_access ? google_secret_manager_secret.bundle : {}
  project   = var.partner_project_id
  secret_id = each.value.id
  role      = "roles/secretmanager.secretVersionAdder"
  member    = local.write_principal
}

# --- Attested reader pool + providers (partner-enforced reads) ---------------
# One reader POOL per partner, one PROVIDER per reader. The keygen write
# pool/provider/CEL above stays UNTOUCHED. That gate is not ours to weaken.
locals {
  # grant_read_access = false is the read kill switch: it also stops the keygen read.
  reshare_read = var.grant_reshare_read && var.grant_read_access
  # One read gate per reader. The keygen gate exists while the keygen image is
  # pinned, and is enabled only for a reshare the partner approves.
  # Disabled, not removed, outside a reshare: a deleted provider id stays reserved for 30 days.
  # Every other gate pins a consumer digest, never the keygen image.
  reader_gates = merge(
    { for k, r in var.attested_readers : k => { gce_project_id = r.gce_project_id, image_digests = [for i in r.images : i.image_digest] } },
    var.image_digest == "" ? {} : { keygen = { gce_project_id = var.service_project_id, image_digests = [var.image_digest] } },
  )
  # dbgstat is pinned for every reader (tightens zee-k).
  reader_condition = { for k, r in local.reader_gates : k => join("\n&& ", [
    "attribute.hwmodel == \"GCP_INTEL_TDX\"",
    "attribute.swname == \"CONFIDENTIAL_SPACE\"",
    "(\",\" + attribute.support_attributes + \",\").contains(\",${var.required_support_attribute},\")",
    "attribute.dbgstat == \"disabled-since-boot\"",
    "attribute.gce_project_id == \"${r.gce_project_id}\"",
    "attribute.image_digest in [${join(", ", [for d in r.image_digests : "\"${d}\""])}]",
  ]) }
}

resource "google_iam_workload_identity_pool" "reader_pool" {
  count                     = length(local.reader_gates) > 0 ? 1 : 0
  project                   = var.partner_project_id
  workload_identity_pool_id = "cofhe-tee-reader-pool"
  depends_on                = [google_project_service.apis]
}

resource "google_iam_workload_identity_pool_provider" "reader" {
  for_each                           = local.reader_gates
  project                            = var.partner_project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.reader_pool[0].workload_identity_pool_id
  workload_identity_pool_provider_id = "${each.key}-reader"
  disabled                           = each.key == "keygen" && !local.reshare_read
  oidc {
    issuer_uri        = var.issuer_uri
    allowed_audiences = ["//iam.googleapis.com/${google_iam_workload_identity_pool.reader_pool[0].name}/providers/${each.key}-reader"]
  }
  attribute_mapping = {
    "google.subject"               = "assertion.sub"
    "attribute.image_digest"       = "assertion.submods.container.image_digest"
    "attribute.hwmodel"            = "assertion.hwmodel"
    "attribute.swname"             = "assertion.swname"
    "attribute.dbgstat"            = "assertion.dbgstat" # NEW vs write provider
    "attribute.support_attributes" = "assertion.submods.confidential_space.support_attributes.join(',')"
    "attribute.gce_project_id"     = "assertion.submods.gce.project_id"
  }
  attribute_condition = local.reader_condition[each.key]
}

# The mirror of attested_add (above): secretAccessor to the attested consumer
# principalSet, always digest-scoped (no unpinned fallback). This is the only read path.
# Keyed by reader and digest, so a release that adds or drops a digest touches
# only that digest's binding.
resource "google_secret_manager_secret_iam_member" "attested_read_image" {
  for_each = var.grant_read_access ? merge([
    for k, r in var.attested_readers : {
      for i in r.images : "${k}@${i.image_digest}" => { secret_id = r.secret_id, image_digest = i.image_digest }
    }
  ]...) : {}
  project   = var.partner_project_id
  secret_id = google_secret_manager_secret.bundle[each.value.secret_id].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.reader_pool[0].name}/attribute.image_digest/${each.value.image_digest}"
}

# The old per-reader bindings hold the same members as the per-digest ones above.
# Forget them without a destroy: a destroy would remove the shared member.
# One time: remove after every partner applies the first list release.
# FIRST-LIST-RELEASE
removed {
  from = google_secret_manager_secret_iam_member.attested_read
  lifecycle {
    destroy = false
  }
}

# Lets the keygen check each partner's newest version before it writes anything.
# Metadata only: it cannot read a share.
resource "google_secret_manager_secret_iam_member" "keygen_version_viewer" {
  for_each  = var.grant_write_access ? google_secret_manager_secret.bundle : {}
  project   = var.partner_project_id
  secret_id = each.value.id
  role      = "roles/secretmanager.viewer"
  member    = local.write_principal
}

# --- Reshare read (keygen image, opt-in) --------------------------------------
# A reshare rebuilds the live key from the current shares and splits it again for
# a new partner set. The keygen image reads both secrets through the `keygen` read
# gate above, which is enabled only while the partner approves the reshare.
# secretAccessor on both secrets, scoped to the keygen image digest in the reader
# pool. A consumer gate pins its own digest, so only the keygen gate can mint this
# principal.
resource "google_secret_manager_secret_iam_member" "reshare_read" {
  for_each  = local.reshare_read ? google_secret_manager_secret.bundle : {}
  project   = var.partner_project_id
  secret_id = each.value.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.reader_pool[0].name}/attribute.image_digest/${var.image_digest}"
}
