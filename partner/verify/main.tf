# Post-apply verification. READ-ONLY.
#
# This root has no `resource` blocks. `terraform plan` here reads the LIVE state of
# the partner project (the deployed CELs and the IAM policy on each secret) and
# asserts it against the same var-file that was applied. A failed assertion is a
# hard error with a message; success is "No changes". It never creates anything.
#
#   terraform -chdir=verify init -backend=false -input=false
#   terraform -chdir=verify plan -input=false \
#     -var-file=../../values.tfvars -var partner_project_id=<your-project>
#
# Needs only read permissions in the partner project (the two viewer roles from
# access/ are enough), so Fhenix can run the identical check.

terraform {
  required_version = ">= 1.9"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

provider "google" {
  project = var.partner_project_id
}

locals {
  reader_pool_id = "cofhe-tee-reader-pool"
  reshare_read   = var.grant_reshare_read && var.grant_read_access
  # The same read gates the module builds. The keygen gate exists while the keygen
  # image is pinned, and is enabled only during a reshare.
  reader_gates = merge(
    { for k, r in var.attested_readers : k => { gce_project_id = r.gce_project_id, image_digests = [for i in r.images : i.image_digest] } },
    var.image_digest == "" ? {} : { keygen = { gce_project_id = var.service_project_id, image_digests = [var.image_digest] } },
  )
  # The full reader-pool principal for an image. A suffix match would also accept
  # the same digest from the write pool, whose gate does not require dbgstat, or
  # from any other pool.
  # The project number comes from the write provider's resource name
  # (projects/<number>/locations/…). The two viewer roles can read it; reading the
  # project itself would need another role.
  partner_number   = split("/", data.google_iam_workload_identity_pool_provider.write.name)[1]
  reader_principal = "principalSet://iam.googleapis.com/projects/${local.partner_number}/locations/global/workloadIdentityPools/${local.reader_pool_id}/attribute.image_digest/"
  keygen_reader    = "${local.reader_principal}${var.image_digest}"
  # The keygen write principal in the write pool; the module grants it the viewer role.
  # As in the module: project-scoped when no keygen image is pinned (dev only). The
  # write gate check below still fails that case.
  write_pool = "principalSet://iam.googleapis.com/projects/${local.partner_number}/locations/global/workloadIdentityPools/${var.pool_id}"
  write_principal = var.image_digest == "" ? (
    "${local.write_pool}/attribute.gce_project_id/${var.service_project_id}"
    ) : (
    "${local.write_pool}/attribute.image_digest/${var.image_digest}"
  )
  # Per secret, the reader principal of every listed consumer image.
  listed_readers = { for s in var.secret_ids : s => flatten([
    for r in var.attested_readers : [for i in r.images : "${local.reader_principal}${i.image_digest}"] if r.secret_id == s
  ]) }
  # Members the module is allowed to bind on a share. Anything else is a finding.
  attested_prefix = "principalSet://iam.googleapis.com/"
}

# --- Write gate --------------------------------------------------------------
data "google_iam_workload_identity_pool_provider" "write" {
  workload_identity_pool_id          = var.pool_id
  workload_identity_pool_provider_id = var.provider_id

  lifecycle {
    postcondition {
      condition     = var.image_digest != "" && strcontains(self.attribute_condition, "attribute.image_digest == \"${var.image_digest}\"")
      error_message = "CHECK FAILED: the write gate does not pin the keygen image.\nExpected image: ${var.image_digest}\nDeployed condition: ${self.attribute_condition}\nDo not change anything. Send this message to Fhenix."
    }
    postcondition {
      condition     = strcontains(self.attribute_condition, "attribute.gce_project_id == \"${var.service_project_id}\"")
      error_message = "CHECK FAILED: the write gate does not pin the Fhenix compute project.\nExpected project: ${var.service_project_id}\nDeployed condition: ${self.attribute_condition}\nDo not change anything. Send this message to Fhenix."
    }
    postcondition {
      condition     = strcontains(self.attribute_condition, "attribute.hwmodel == \"GCP_INTEL_TDX\"") && strcontains(self.attribute_condition, "attribute.swname == \"CONFIDENTIAL_SPACE\"")
      error_message = "CHECK FAILED: the write gate does not require Intel TDX Confidential Space.\nDeployed condition: ${self.attribute_condition}\nDo not change anything. Send this message to Fhenix."
    }
  }
}

# --- Read gates (one per reader) --------------------------------------------
data "google_iam_workload_identity_pool_provider" "reader" {
  for_each                           = local.reader_gates
  workload_identity_pool_id          = local.reader_pool_id
  workload_identity_pool_provider_id = "${each.key}-reader"

  lifecycle {
    postcondition {
      condition     = strcontains(self.attribute_condition, "attribute.image_digest in [${join(", ", [for d in each.value.image_digests : "\"${d}\""])}]")
      error_message = "CHECK FAILED: the ${each.key} read gate does not pin exactly the listed ${each.key} images.\n${alltrue([for d in each.value.image_digests : strcontains(self.attribute_condition, "\"${d}\"")]) ? "No listed image is missing: the order differs from values.tfvars, or the gate lists an extra image." : "Missing: ${join(", ", [for d in each.value.image_digests : d if !strcontains(self.attribute_condition, "\"${d}\"")])}"}\nExpected images: ${join(", ", each.value.image_digests)}\nDeployed condition: ${self.attribute_condition}\nDo not change anything. Send this message to Fhenix."
    }
    postcondition {
      condition     = strcontains(self.attribute_condition, "attribute.gce_project_id == \"${each.value.gce_project_id}\"")
      error_message = "CHECK FAILED: the ${each.key} read gate does not pin the compute project.\nExpected project: ${each.value.gce_project_id}\nDeployed condition: ${self.attribute_condition}\nDo not change anything. Send this message to Fhenix."
    }
    postcondition {
      condition     = strcontains(self.attribute_condition, "attribute.hwmodel == \"GCP_INTEL_TDX\"") && strcontains(self.attribute_condition, "attribute.swname == \"CONFIDENTIAL_SPACE\"")
      error_message = "CHECK FAILED: the ${each.key} read gate does not require Intel TDX Confidential Space.\nDeployed condition: ${self.attribute_condition}\nDo not change anything. Send this message to Fhenix."
    }
    postcondition {
      condition     = strcontains(self.attribute_condition, "attribute.dbgstat == \"disabled-since-boot\"")
      error_message = "CHECK FAILED: the ${each.key} read gate does not require debugging disabled since boot.\nDeployed condition: ${self.attribute_condition}\nDo not change anything. Send this message to Fhenix."
    }
    postcondition {
      condition     = self.disabled == (each.key == "keygen" && !local.reshare_read)
      error_message = each.key == "keygen" && !local.reshare_read ? "CHECK FAILED: the keygen read gate is enabled, but the reshare read is off (grant_reshare_read or grant_read_access is false).\nDo not change anything. Send this message to Fhenix." : "CHECK FAILED: the ${each.key} read gate is disabled. Reads through it fail.\nDo not change anything. Send this message to Fhenix."
    }
  }
}

# --- Who can touch each share ------------------------------------------------
data "google_secret_manager_secret_iam_policy" "secret" {
  for_each  = toset(var.secret_ids)
  secret_id = each.key

  lifecycle {
    # Every member on the secret must be an attested principalSet, never a person
    # or a service account.
    postcondition {
      condition = alltrue([
        for b in lookup(jsondecode(self.policy_data), "bindings", []) : alltrue([
          for m in b.members : startswith(m, local.attested_prefix)
        ])
      ])
      error_message = "CHECK FAILED: an identity that is not an attested enclave can read the share ${each.key}.\nUnexpected identities: ${join(", ", [for b in lookup(jsondecode(self.policy_data), "bindings", []) : join(", ", [for m in b.members : m if !startswith(m, local.attested_prefix)])])}\nDo not change anything. Send this message to Fhenix."
    }
    # Exactly one reader binding, or none while the brake (grant_read_access =
    # false) is on. Its members are checked below.
    postcondition {
      condition = length([
        for b in lookup(jsondecode(self.policy_data), "bindings", []) : b
        if b.role == "roles/secretmanager.secretAccessor"
      ]) == (var.grant_read_access ? 1 : 0)
      error_message = var.grant_read_access ? "CHECK FAILED: the share ${each.key} must have exactly one reader binding.\nDeployed policy: ${self.policy_data}\nDo not change anything. Send this message to Fhenix." : "CHECK FAILED: the share ${each.key} still has a reader binding, but grant_read_access is false.\nDeployed policy: ${self.policy_data}\nDo not change anything. Send this message to Fhenix."
    }
    # The module never sets an IAM condition on a binding for its own pools. A
    # conditional one can be inert, so it would look right here and grant nothing.
    postcondition {
      condition = alltrue([
        for b in lookup(jsondecode(self.policy_data), "bindings", []) : !contains(keys(b), "condition")
        if contains(["roles/secretmanager.viewer", "roles/secretmanager.secretVersionAdder", "roles/secretmanager.secretAccessor"], b.role)
        && anytrue([for m in b.members : startswith(m, "${local.write_pool}/") || startswith(m, "${local.reader_principal}")])
      ])
      error_message = "CHECK FAILED: a binding on the share ${each.key} has an IAM condition. The module sets none.\nDeployed policy: ${self.policy_data}\nDo not change anything. Send this message to Fhenix."
    }
    # Every reader is a consumer image named in values.tfvars, or the keygen image
    # during a reshare.
    postcondition {
      condition = alltrue(flatten([
        for b in lookup(jsondecode(self.policy_data), "bindings", []) : [
          for m in b.members : anytrue(concat([
            for r in var.attested_readers : anytrue([for i in r.images : m == "${local.reader_principal}${i.image_digest}"]) if r.secret_id == each.key
          ], [local.reshare_read && m == local.keygen_reader]))
        ] if b.role == "roles/secretmanager.secretAccessor"
      ]))
      error_message = "CHECK FAILED: a reader of the share ${each.key} is not an image named in values.tfvars.\nDeployed policy: ${self.policy_data}\nDo not change anything. Send this message to Fhenix."
    }
    # Every listed consumer image is a reader. The check above only rejects extra
    # members; a missing one locks that consumer out.
    postcondition {
      condition = !var.grant_read_access || length(setsubtract(local.listed_readers[each.key], flatten([
        for b in lookup(jsondecode(self.policy_data), "bindings", []) : b.members if b.role == "roles/secretmanager.secretAccessor"
      ]))) == 0
      error_message = "CHECK FAILED: a listed image cannot read the share ${each.key}. Its consumers are locked out.\nMissing: ${join(", ", setsubtract(local.listed_readers[each.key], flatten([for b in lookup(jsondecode(self.policy_data), "bindings", []) : b.members if b.role == "roles/secretmanager.secretAccessor"])))}\nDo not change anything. Send this message to Fhenix."
    }
    # The keygen image is a reader only while grant_reshare_read = true.
    postcondition {
      condition = anytrue(flatten([
        for b in lookup(jsondecode(self.policy_data), "bindings", []) : [
          for m in b.members : m == local.keygen_reader
        ] if b.role == "roles/secretmanager.secretAccessor"
      ])) == local.reshare_read
      error_message = local.reshare_read ? "CHECK FAILED: the keygen image cannot read the share ${each.key}, but grant_reshare_read is true. The reshare would fail.\nDo not change anything. Send this message to Fhenix." : "CHECK FAILED: the keygen image can still read the share ${each.key}, but the reshare read is off (grant_reshare_read or grant_read_access is false).\nDo not change anything. Send this message to Fhenix."
    }
    # The keygen lists versions only in the write window: one viewer binding, held
    # by the keygen write principal alone.
    postcondition {
      condition = alltrue([
        for b in lookup(jsondecode(self.policy_data), "bindings", []) : b.members == [local.write_principal]
        if b.role == "roles/secretmanager.viewer"
        ]) && length([
        for b in lookup(jsondecode(self.policy_data), "bindings", []) : b
        if b.role == "roles/secretmanager.viewer"
      ]) == (var.grant_write_access ? 1 : 0)
      error_message = var.grant_write_access ? "CHECK FAILED: the share ${each.key} must have exactly one list binding, held by the keygen write principal, because grant_write_access is true.\nDeployed policy: ${self.policy_data}\nDo not change anything. Send this message to Fhenix." : "CHECK FAILED: the share ${each.key} has a list binding, but grant_write_access is false.\nDeployed policy: ${self.policy_data}\nDo not change anything. Send this message to Fhenix."
    }
    # Write binding present only while grant_write_access = true (ceremony window).
    postcondition {
      condition = length([
        for b in lookup(jsondecode(self.policy_data), "bindings", []) : b
        if b.role == "roles/secretmanager.secretVersionAdder"
      ]) == (var.grant_write_access ? 1 : 0)
      error_message = var.grant_write_access ? "CHECK FAILED: the share ${each.key} has no write binding, but grant_write_access is true. The ceremony would fail.\nDo not change anything. Send this message to Fhenix." : "CHECK FAILED: the share ${each.key} is still writable. grant_write_access is false, but a write binding is present.\nDo not change anything. Send this message to Fhenix."
    }
  }
}

output "SUCCESS" {
  description = "Printed only when every check passed. All gates and share permissions match values.tfvars."
  value = {
    partner_project      = var.partner_project_id
    write_gate_pins      = var.image_digest
    read_gates_pin       = { for k, r in var.attested_readers : k => [for i in r.images : i.image_digest] }
    write_access_granted = var.grant_write_access
    reshare_read_granted = local.reshare_read
  }
}
