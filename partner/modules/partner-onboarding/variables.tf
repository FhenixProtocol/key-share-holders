variable "partner_project_id" {
  type        = string
  description = "The partner's GCP project. Holds the Secret Manager secret(s) that receive the key share, plus the WIP pool/provider that gates our attested write."
}

variable "service_project_id" {
  type        = string
  description = "Our keygen service's compute project. The CEL pins this (attribute.gce_project_id) and the secretVersionAdder grant targets the federated principal scoped to it, so only attestations from VMs in this project can write."

  # Interpolated straight into the CEL attribute_condition and the principalSet
  # grant; reject anything that isn't a well-formed GCP project id so a malformed
  # value can't reshape the gate.
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.service_project_id))
    error_message = "service_project_id must be a valid GCP project id (6-30 chars: lowercase letters, digits, hyphens; start with a letter, end alphanumeric)."
  }
}

variable "secret_ids" {
  type        = list(string)
  default     = ["cofhe-tee-fhe-priv", "cofhe-tee-zk-signer"]
  description = "Per-audience Secret Manager secrets that receive the generated key components as new versions: cofhe-tee-fhe-priv (FHE priv + decrypt signer → TeeCryptor) and cofhe-tee-zk-signer (zk signer → ZK verifier). The enclave is granted secretVersionAdder on each; each consumer is granted attested read only on the secret it needs."
}

variable "image_digest" {
  type        = string
  default     = ""
  description = "If non-empty (e.g. \"sha256:abc...\"), the CEL additionally pins attribute.image_digest to exactly this image, the strongest gate (partner re-applies on every image rebuild). Leave empty during early dev to redeploy the service without a partner re-apply."

  # Interpolated into the CEL attribute_condition; only accept an empty string
  # (unpinned) or a canonical sha256 digest, so a malformed value can't inject
  # extra CEL and neutralize the image pin.
  validation {
    condition     = var.image_digest == "" || can(regex("^sha256:[a-f0-9]{64}$", var.image_digest))
    error_message = "image_digest must be empty or a canonical digest of the form \"sha256:<64 lowercase hex>\"."
  }
}

variable "grant_write_access" {
  type = bool
  # DEFAULT FALSE, fail safe. The keygen write is bootstrap-only: it is needed
  # for the one ceremony apply and must be off the rest of the time. Defaulting
  # to true made "forgot to pass the flag" silently RE-GRANT write access on any
  # later re-apply (e.g. re-pinning a consumer image digest); defaulting to false
  # makes the same mistake revoke instead, which is the safe direction and is
  # visible in the plan as a destroy. Pass `-var grant_write_access=true` on the
  # partner apply that precedes a ceremony, then drop it.
  default     = false
  description = "Whether to grant our attested enclave secretVersionAdder on the secret(s). Defaults FALSE (frozen). Set true ONLY for the partner apply that precedes a key ceremony; the pool/provider and secret are untouched either way, so it is fully reversible."
}

variable "attested_readers" {
  type = map(object({       # key = consumer name: "teecryptor" | "zee-k"
    gce_project_id = string # consumer's COMPUTE project (fhenix-compute-project)
    image_digest   = string # consumer's image digest, REQUIRED non-empty (guardrail)
    secret_id      = string # the ONE secret this consumer may read
  }))
  default = {}
  validation {
    condition     = alltrue([for r in values(var.attested_readers) : can(regex("^sha256:[a-f0-9]{64}$", r.image_digest))])
    error_message = "every attested reader must pin a canonical sha256 image digest (never unpinned: the reader CEL must not be satisfiable by the keygen image)."
  }
  validation {
    condition     = alltrue([for r in values(var.attested_readers) : can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", r.gce_project_id))])
    error_message = "gce_project_id must be a valid GCP project id."
  }
  validation {
    condition     = alltrue([for r in values(var.attested_readers) : contains(var.secret_ids, r.secret_id)])
    error_message = "each attested reader's secret_id must be one of secret_ids."
  }
  validation {
    condition     = alltrue([for k in keys(var.attested_readers) : can(regex("^[a-z][a-z0-9-]{2,20}$", k))])
    error_message = "consumer keys become provider ids (<key>-reader); keep them short lowercase slugs."
  }
}

# Revocable like grant_write_access, but the DEFAULT is the opposite: reads are the
# steady state (consumers re-read on every boot), so this defaults TRUE and
# revoking is an emergency brake, whereas write is bootstrap-only and defaults off.
variable "grant_read_access" {
  type    = bool
  default = true
}

variable "pool_id" {
  type        = string
  default     = "cofhe-tee-keygen-pool"
  description = "Workload Identity Pool id created in the partner project."
}

variable "provider_id" {
  type        = string
  default     = "cofhe-tee-keygen-provider"
  description = "Workload Identity Pool Provider id (the OIDC provider for Confidential Space tokens)."
}

variable "required_support_attribute" {
  type        = string
  default     = "STABLE"
  description = "Confidential Space image support attribute the CEL requires (STABLE rejects DEBUG/experimental images)."
}

variable "issuer_uri" {
  type        = string
  default     = "https://confidentialcomputing.googleapis.com"
  description = "OIDC issuer of Confidential Space attestation tokens."
}
