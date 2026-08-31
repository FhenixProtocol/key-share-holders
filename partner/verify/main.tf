# Post-apply verification — READ-ONLY.
#
# This root has no `resource` blocks. `terraform plan` here reads the LIVE state of
# the partner project (the deployed CELs and the IAM policy on each secret) and
# asserts it against the same var-file that was applied. A failed assertion is a
# hard error with a message; success is "No changes" — it never creates anything.
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

# --- Read gates (one per consumer) ------------------------------------------
data "google_iam_workload_identity_pool_provider" "reader" {
  for_each                           = var.attested_readers
  workload_identity_pool_id          = local.reader_pool_id
  workload_identity_pool_provider_id = "${each.key}-reader"

  lifecycle {
    postcondition {
      condition     = strcontains(self.attribute_condition, "attribute.image_digest == \"${each.value.image_digest}\"")
      error_message = "CHECK FAILED: the ${each.key} read gate does not pin the ${each.key} image.\nExpected image: ${each.value.image_digest}\nDeployed condition: ${self.attribute_condition}\nDo not change anything. Send this message to Fhenix."
    }
    postcondition {
      condition     = strcontains(self.attribute_condition, "attribute.gce_project_id == \"${each.value.gce_project_id}\"")
      error_message = "CHECK FAILED: the ${each.key} read gate does not pin the compute project.\nExpected project: ${each.value.gce_project_id}\nDeployed condition: ${self.attribute_condition}\nDo not change anything. Send this message to Fhenix."
    }
    postcondition {
      condition     = strcontains(self.attribute_condition, "attribute.dbgstat == \"disabled-since-boot\"")
      error_message = "CHECK FAILED: the ${each.key} read gate does not require debugging disabled since boot.\nDeployed condition: ${self.attribute_condition}\nDo not change anything. Send this message to Fhenix."
    }
  }
}

# --- Who can touch each share ------------------------------------------------
data "google_secret_manager_secret_iam_policy" "secret" {
  for_each  = toset(var.secret_ids)
  secret_id = each.key

  lifecycle {
    # Every member on the secret must be an attested principalSet — never a person
    # or a service account.
    postcondition {
      condition = alltrue([
        for b in jsondecode(self.policy_data).bindings : alltrue([
          for m in b.members : startswith(m, local.attested_prefix)
        ])
      ])
      error_message = "CHECK FAILED: an identity that is not an attested enclave can read the share ${each.key}.\nUnexpected identities: ${join(", ", [for b in jsondecode(self.policy_data).bindings : join(", ", [for m in b.members : m if !startswith(m, local.attested_prefix)])])}\nDo not change anything. Send this message to Fhenix."
    }
    # Exactly one attested reader, scoped to the consumer image that owns this secret.
    postcondition {
      condition = length([
        for b in jsondecode(self.policy_data).bindings : b
        if b.role == "roles/secretmanager.secretAccessor"
      ]) == 1
      error_message = "CHECK FAILED: the share ${each.key} must have exactly one reader binding.\nDeployed policy: ${self.policy_data}\nDo not change anything. Send this message to Fhenix."
    }
    postcondition {
      condition = alltrue(flatten([
        for b in jsondecode(self.policy_data).bindings : [
          for m in b.members : anytrue([
            for r in var.attested_readers : endswith(m, "/attribute.image_digest/${r.image_digest}") if r.secret_id == each.key
          ])
        ] if b.role == "roles/secretmanager.secretAccessor"
      ]))
      error_message = "CHECK FAILED: the reader of the share ${each.key} is not the consumer image named in values.tfvars.\nDeployed policy: ${self.policy_data}\nDo not change anything. Send this message to Fhenix."
    }
    # Write binding present only while grant_write_access = true (ceremony window).
    postcondition {
      condition = length([
        for b in jsondecode(self.policy_data).bindings : b
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
    read_gates_pin       = { for k, r in var.attested_readers : k => r.image_digest }
    write_access_granted = var.grant_write_access
  }
}
