# The reshare read gate decides who can read a key share. These runs pin its logic
# with a mock provider: no credentials, no project.
mock_provider "google" {}

variables {
  partner_project_id = "partner-proj-1"
  service_project_id = "fhenix-keygen-svc"
  secret_ids         = ["cofhe-tee-fhe-priv", "cofhe-tee-zk-signer"]
  image_digest       = "sha256:1111111111111111111111111111111111111111111111111111111111111111"
  attested_readers = {
    teecryptor = {
      gce_project_id = "fhenix-tc-proj"
      image_digest   = "sha256:2222222222222222222222222222222222222222222222222222222222222222"
      secret_id      = "cofhe-tee-fhe-priv"
    }
  }
}

run "flag_off_gate_disabled" {
  command = plan
  variables {
    grant_reshare_read = false
  }
  assert {
    condition     = google_iam_workload_identity_pool_provider.reader["keygen"].disabled
    error_message = "the keygen gate must exist, disabled, outside a reshare"
  }
  assert {
    condition     = !google_iam_workload_identity_pool_provider.reader["teecryptor"].disabled
    error_message = "a consumer gate is never disabled"
  }
  assert {
    condition     = length(google_secret_manager_secret_iam_member.reshare_read) == 0
    error_message = "no keygen read grant outside a reshare"
  }
}

run "flag_on" {
  command = plan
  variables {
    grant_reshare_read = true
  }
  assert {
    condition     = !google_iam_workload_identity_pool_provider.reader["keygen"].disabled
    error_message = "the keygen gate is enabled during a reshare"
  }
  assert {
    condition = alltrue([for want in [
      "attribute.image_digest == \"sha256:1111111111111111111111111111111111111111111111111111111111111111\"",
      "attribute.gce_project_id == \"fhenix-keygen-svc\"",
      "attribute.dbgstat == \"disabled-since-boot\"",
      "attribute.hwmodel == \"GCP_INTEL_TDX\"",
    ] : strcontains(google_iam_workload_identity_pool_provider.reader["keygen"].attribute_condition, want)])
    error_message = "the keygen gate pins the keygen digest, the compute project, dbgstat and TDX"
  }
  assert {
    condition     = length(google_secret_manager_secret_iam_member.reshare_read) == 2
    error_message = "the keygen image reads both secrets during a reshare"
  }
  assert {
    condition     = !contains(keys(output.reader_wip_audiences), "keygen")
    error_message = "the keygen gate is not a consumer audience"
  }
}

run "read_brake_wins" {
  command = plan
  variables {
    grant_reshare_read = true
    grant_read_access  = false
  }
  assert {
    condition     = google_iam_workload_identity_pool_provider.reader["keygen"].disabled
    error_message = "grant_read_access = false disables the keygen gate"
  }
  assert {
    condition     = length(google_secret_manager_secret_iam_member.reshare_read) == 0
    error_message = "grant_read_access = false removes the keygen read grant"
  }
}

# A WIF pool is soft-deleted for 30 days, so a partner with no consumers must keep
# the pool, and a disabled keygen gate, while the flag is off.
run "pool_kept_without_consumers" {
  command = plan
  variables {
    attested_readers   = {}
    grant_reshare_read = false
  }
  assert {
    condition     = length(google_iam_workload_identity_pool.reader_pool) == 1 && google_iam_workload_identity_pool_provider.reader["keygen"].disabled
    error_message = "a pinned keygen digest keeps the reader pool and a disabled keygen gate"
  }
}

run "flag_needs_a_pinned_digest" {
  command = plan
  variables {
    image_digest       = ""
    grant_reshare_read = true
  }
  expect_failures = [var.grant_reshare_read]
}

run "keygen_key_is_reserved" {
  command = plan
  variables {
    attested_readers = {
      keygen = {
        gce_project_id = "fhenix-tc-proj"
        image_digest   = "sha256:2222222222222222222222222222222222222222222222222222222222222222"
        secret_id      = "cofhe-tee-fhe-priv"
      }
    }
  }
  expect_failures = [var.attested_readers]
}
