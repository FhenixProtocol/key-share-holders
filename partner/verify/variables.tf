# Same names and types as ../variables.tf so the release's values.tfvars is
# passed through unchanged. Inputs the check does not need are declared but unused.

variable "partner_project_id" {
  type = string
}

variable "service_project_id" {
  type = string
}

variable "secret_ids" {
  type    = list(string)
  default = ["cofhe-tee-fhe-priv", "cofhe-tee-zk-signer"]
}

variable "image_digest" {
  type    = string
  default = ""
}

variable "source_sha" {
  type    = string
  default = ""
}

variable "grant_write_access" {
  type    = bool
  default = false
}

variable "attested_readers" {
  type = map(object({
    gce_project_id = string
    secret_id      = string
    images = list(object({
      image_digest = string
      # optional(), so this root still runs against a var-file from before
      # source_sha existed. It is unused here; the gate lives in ../provenance.tf.
      source_sha = optional(string, "")
    }))
  }))
  default = {}

  validation {
    condition     = alltrue([for r in values(var.attested_readers) : length(r.images) >= 1 && length(r.images) <= 2])
    error_message = "every attested reader lists 1 or 2 images."
  }

  validation {
    condition     = alltrue(flatten([for r in values(var.attested_readers) : [for i in r.images : can(regex("^sha256:[0-9a-f]{64}$", i.image_digest))]]))
    error_message = "every attested reader must pin \"sha256:\" plus 64 lowercase hex characters."
  }

  validation {
    condition     = alltrue([for r in values(var.attested_readers) : length(distinct([for i in r.images : i.image_digest])) == length(r.images)])
    error_message = "the digests of one attested reader must be distinct."
  }
}

variable "grant_read_access" {
  type    = bool
  default = true
}

variable "grant_reshare_read" {
  type    = bool
  default = false
}

variable "pool_id" {
  type    = string
  default = "cofhe-tee-keygen-pool"
}

variable "provider_id" {
  type    = string
  default = "cofhe-tee-keygen-provider"
}
