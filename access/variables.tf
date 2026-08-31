variable "partner_project_id" {
  type        = string
  description = "The partner's GCP project to grant read-only operator access in (e.g. <your-project>). Run once per partner."
}

variable "operators" {
  type        = list(string)
  default     = ["group:protocol@fhenix.io"]
  description = "IAM members granted read-only verification access in this project. Never granted write: see the header of main.tf for why the partner runs partner/ themselves."
}

variable "grant_view_access" {
  type = bool
  # Defaults TRUE, unlike grant_write_access: read-only verification is the steady
  # state, and these roles cannot reach a share, so "on" is the safe default here.
  # The trade-off is the mirror of the write flag — a revoke via
  # `-var grant_view_access=false` is undone by any later apply that omits it, so a
  # partner who wants access permanently withdrawn should set it in their tfvars,
  # not pass it on the command line.
  default     = true
  description = "Set false to REVOKE Fhenix's read-only verification access (removes both role bindings; nothing else is touched, fully reversible). Persist it in terraform.tfvars, not just -var, or a later apply re-grants. Removes only Terraform-tracked bindings — confirm with `gcloud projects get-iam-policy`. After revoking we can no longer verify their gates and every check falls back to asking them."
}
