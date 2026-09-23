output "granted_roles" {
  # Derived from the RESOURCE, not from the variable, so it reports what is
  # actually bound rather than what the config intended.
  value       = distinct([for b in google_project_iam_member.verify : b.role])
  description = "Predefined read-only roles actually bound to the operators in this partner project. Empty when grant_view_access = false."
}

output "granted_project" {
  value       = var.partner_project_id
  description = "Partner project the roles were granted in."
}

output "operators" {
  value       = var.operators
  description = "Members granted read-only access in this project."
}
