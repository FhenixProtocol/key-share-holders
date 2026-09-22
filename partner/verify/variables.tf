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
    image_digest   = string
    # optional(), so this root still runs against a var-file from before
    # source_sha existed. It is unused here; the gate lives in ../provenance.tf.
    source_sha = optional(string, "")
    secret_id  = string
  }))
  default = {}
}

variable "grant_read_access" {
  type    = bool
  default = true
}

variable "pool_id" {
  type    = string
  default = "cofhe-tee-keygen-pool"
}

variable "provider_id" {
  type    = string
  default = "cofhe-tee-keygen-provider"
}
