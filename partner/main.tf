terraform {
  required_version = ">= 1.9"
  # Remote state in the PARTNER's OWN project bucket — one bucket per partner, not
  # a shared per-env bucket (the env buckets hold only `service` and
  # `keygen-project`). Bucket + prefix are passed at init (partial config):
  #   terraform init -reconfigure \
  #     -backend-config="bucket=<partner-project>-tfstate" \
  #     -backend-config="prefix=cofhe-tdx-keygen/partner"
  backend "gcs" {}
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.0" }
  }
}

provider "google" {
  project = var.partner_project_id
}

# Partner stack — a thin root that invokes the reusable partner-onboarding
# module. This is exactly what a real partner would run: point the module at our
# service project, apply, and hand back the outputs. Kept as a single instance
# here (<your-project>); the module itself is partner-agnostic.
module "onboarding" {
  source = "./modules/partner-onboarding"

  partner_project_id = var.partner_project_id
  service_project_id = var.service_project_id
  secret_ids         = var.secret_ids
  image_digest       = var.image_digest
  grant_write_access = var.grant_write_access
  attested_readers   = var.attested_readers
  grant_read_access  = var.grant_read_access
}

# --- Outputs (handed to the service side) -------------------------------
output "wip_audience" {
  value = module.onboarding.wip_audience
}

output "partner_project_id" {
  value = module.onboarding.partner_project_id
}

output "secret_ids" {
  value = var.secret_ids
}

output "reader_wip_audiences" {
  value = module.onboarding.reader_wip_audiences
}
