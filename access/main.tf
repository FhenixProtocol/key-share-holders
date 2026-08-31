# Per-partner operator access — run ONCE per partner project, by the partner.
#
# Fhenix operators get READ-ONLY access, permanently. Two PREDEFINED Google roles:
#
#   roles/secretmanager.viewer            secrets.get/list/getIamPolicy, versions.get/list
#   roles/iam.workloadIdentityPoolViewer  pools + providers get/list (i.e. read the CEL)
#
# That is enough to verify everything without asking the partner: that the CEL pins
# the expected image digest, that the IAM bindings are the expected attested
# principals, and that a ceremony landed (version METADATA — names, states,
# timestamps). It cannot read a share (no `secretmanager.versions.access`) and
# cannot change anything.
#
# Predefined rather than a custom role on purpose: a partner audits two
# Google-documented roles instead of trusting a hand-written permission list.
#
# Trade-off accepted: a project custom role was a single revoke chokepoint —
# deleting it killed every binding to it, tracked by Terraform or not. Predefined
# roles have no such chokepoint, so `grant_view_access = false` removes only the
# bindings in state. A binding added out-of-band survives it. Verify a revoke with
# `gcloud projects get-iam-policy`, never by assuming.
#
# WHY WE DELIBERATELY DO NOT TAKE WRITE ACCESS
#
# `partner/` needs `secretmanager.secrets.setIamPolicy` — setting
# per-secret IAM is its entire job — and whoever holds that can self-grant
# `secretAccessor` and read the share. Two partners reach T=2 and the network key
# is reconstructable.
#
# Time-boxing that permission does NOT fix it. A binding created out-of-band (say
# by `gcloud secrets add-iam-policy-binding`) is not in Terraform state, and every
# IAM resource in this repo is additive `*_iam_member`, so nothing later removes
# it: a grant planted while the secrets are empty survives indefinitely and goes
# live the moment a share is written. So the boundary cannot be time — the partner
# runs `partner/` themselves and we never hold the permission at all.
#
# The ceremony does not need it either. The keygen enclave authenticates with TDX
# attestation against the partner's own CEL; no operator credential is ever in the
# security path.
#
# Run once per partner (its state lives in that partner's own bucket):
#   terraform init -reconfigure \
#     -backend-config="bucket=<partner-project>-tfstate" \
#     -backend-config="prefix=cofhe-tdx-keygen/access"
#   terraform apply -var="partner_project_id=<partner-project>"
#
# See ../../PERMISSIONS.md.

terraform {
  required_version = ">= 1.9"
  backend "gcs" {}
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.0" }
  }
}

provider "google" {
  project = var.partner_project_id
}

locals {
  # Read-only, predefined. Neither grants secretmanager.versions.access (the share
  # bytes) nor secrets.setIamPolicy (the escalation path to them).
  verify_roles = [
    "roles/secretmanager.viewer",
    "roles/iam.workloadIdentityPoolViewer",
  ]

  verify_bindings = var.grant_view_access ? {
    for pair in setproduct(var.operators, local.verify_roles) :
    "${pair[0]}::${pair[1]}" => { member = pair[0], role = pair[1] }
  } : {}
}

resource "google_project_iam_member" "verify" {
  for_each = local.verify_bindings
  project  = var.partner_project_id
  role     = each.value.role
  member   = each.value.member
}
