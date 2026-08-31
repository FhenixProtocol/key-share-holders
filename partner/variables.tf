variable "partner_project_id" {
  type        = string
  description = "Partner's GCP project holding their Secret Manager + WIP/provider (e.g. <your-project>)."
}

variable "service_project_id" {
  type = string
  # NO DEFAULT, deliberately. It used to default to our own dev keygen project, so an apply
  # that forgot `-var-file` silently pinned the partner's write CEL to that project
  # instead of the env's real compute project — a wrong gate, applied without error.
  # Required now, so the same mistake fails loudly at plan time.
  description = "Our keygen service's compute project for THIS env (e.g. fhenix-compute-project). The CEL pins it — only attestations from VMs in this project may write to the secret (a direct federated grant). Comes from the env's gitops keygen-partners var-file; there is no default."
}

variable "secret_ids" {
  type        = list(string)
  default     = ["cofhe-tee-fhe-priv", "cofhe-tee-zk-signer"]
  description = "Per-audience Secret Manager secrets that receive the generated key components: cofhe-tee-fhe-priv (FHE priv + decrypt signer → TeeCryptor) and cofhe-tee-zk-signer (zk signer → ZK verifier)."
}

variable "image_digest" {
  type        = string
  default     = ""
  description = "Optional exact image pin (sha256:...). Empty = unpinned (early dev). Set to require a partner re-apply on every keygen image rebuild."
}

variable "grant_write_access" {
  type        = bool
  default     = false
  description = "Defaults FALSE (frozen) so a routine re-apply can never silently re-grant write. Set true ONLY for the partner apply preceding a key ceremony; removes/adds the secretVersionAdder binding (secret + pool kept; reversible). The keygen write is bootstrap-only."
}

variable "attested_readers" {
  type = map(object({
    gce_project_id = string
    image_digest   = string
    secret_id      = string
  }))
  default     = {}
  description = "Attested reader consumers (key = consumer name, e.g. \"teecryptor\" / \"zee-k\"): each gets a WIP provider under the partner's reader pool whose CEL pins the consumer's compute project + exact image digest, plus a digest-scoped secretAccessor grant on ONLY its secret_id. Empty = no read path at all."
}

variable "grant_read_access" {
  type        = bool
  default     = true
  description = "Set false to REVOKE the attested readers' secretAccessor bindings (pool/providers and secrets kept; reversible). Defaults TRUE — unlike grant_write_access, reads are the steady state: consumers re-read the shares on every boot, so revoking is an emergency brake, not a post-bootstrap step."
}
