# The onboarding "return tuple": what the partner sends back to us after apply.
# We register these in our partner registry; the keygen job reads them to know
# which audience to attest for and which secret(s) to write. No SA, no bucket
# (direct federated grant + public material in our bucket).

output "wip_audience" {
  description = "Audience the keygen workload requests from the CS launcher and presents to STS for this partner."
  value       = "//iam.googleapis.com/${google_iam_workload_identity_pool.pool.name}/providers/${var.provider_id}"
}

output "partner_project_id" {
  description = "The partner's project id (registry key)."
  value       = var.partner_project_id
}

output "secret_ids" {
  description = "Secret Manager secret ids that receive the key share."
  value       = var.secret_ids
}

output "image_pinned" {
  description = "Whether the CEL pins an exact image_digest (true = partner must re-apply on each image rebuild)."
  value       = var.image_digest != ""
}

output "write_access_granted" {
  description = "Whether our attested enclave currently holds secretVersionAdder on the secret(s). False = revoked (we can no longer add a version)."
  value       = var.grant_write_access
}

output "reader_wip_audiences" {
  description = "Per-consumer audience the reader enclave attests for at THIS partner."
  value = { for k, p in google_iam_workload_identity_pool_provider.reader :
  k => "//iam.googleapis.com/${p.name}" }
}
