terraform {
  required_version = ">= 1.9"
  # Remote state in the PARTNER's OWN project bucket: one bucket per partner, not
  # a shared per-env bucket (the env buckets hold only `service` and
  # `keygen-project`). Bucket + prefix are passed at init (partial config):
  #   terraform init -reconfigure \
  #     -backend-config="bucket=<partner-project>-tfstate" \
  #     -backend-config="prefix=cofhe-tdx-keygen/partner"
  backend "gcs" {}
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.0" }
    # Runs the provenance check in provenance.tf. It creates nothing.
    external = { source = "hashicorp/external", version = "~> 2.3" }
  }
}

provider "google" {
  project = var.partner_project_id
}

# Partner stack: a thin root that invokes the reusable partner-onboarding
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
  grant_read_access  = var.grant_read_access

  # source_sha is dropped here, deliberately. It is proof material for the
  # provenance gate, not gate material. The CEL pins the image digest and
  # nothing else, so the commit must never reach the module that writes the CEL.
  # Stripping it in one visible place keeps that invariant readable.
  attested_readers = {
    for k, r in var.attested_readers : k => {
      gce_project_id = r.gce_project_id
      image_digest   = r.image_digest
      secret_id      = r.secret_id
    }
  }

  # Nothing is created until every digest has been proven to come from the
  # commit we published beside it.
  depends_on = [data.external.provenance]
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
