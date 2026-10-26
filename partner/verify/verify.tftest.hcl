# Offline check of the share-policy postconditions. Mocked provider; nothing is read live.
mock_provider "google" {
  mock_data "google_iam_workload_identity_pool_provider" {
    defaults = {
      name                = "projects/123/locations/global/workloadIdentityPools/cofhe-tee-keygen-pool/providers/cofhe-tee-keygen-provider"
      disabled            = true
      attribute_condition = "attribute.hwmodel == \"GCP_INTEL_TDX\"\n&& attribute.swname == \"CONFIDENTIAL_SPACE\"\n&& (\",\" + attribute.support_attributes + \",\").contains(\",STABLE,\")\n&& attribute.gce_project_id == \"compute\"\n&& attribute.image_digest == \"sha256:1111111111111111111111111111111111111111111111111111111111111111\""
    }
  }
}

variables {
  partner_project_id = "fixture"
  service_project_id = "compute"
  secret_ids         = ["s"]
  image_digest       = "sha256:1111111111111111111111111111111111111111111111111111111111111111"
  grant_read_access  = false
  grant_write_access = true
}

# The mock default above is the write gate. The keygen read gate and a valid share
# policy are the base for each run; a run changes one of them.
override_data {
  target = data.google_iam_workload_identity_pool_provider.reader["keygen"]
  values = {
    name                = "projects/123/locations/global/workloadIdentityPools/cofhe-tee-reader-pool/providers/keygen-reader"
    disabled            = true
    attribute_condition = "attribute.hwmodel == \"GCP_INTEL_TDX\"\n&& attribute.swname == \"CONFIDENTIAL_SPACE\"\n&& (\",\" + attribute.support_attributes + \",\").contains(\",STABLE,\")\n&& attribute.dbgstat == \"disabled-since-boot\"\n&& attribute.gce_project_id == \"compute\"\n&& attribute.image_digest in [\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"]"
  }
}

override_data {
  target = data.google_secret_manager_secret_iam_policy.secret["s"]
  values = {
    policy_data = <<-EOT
    {
      "bindings": [
        {
          "role": "roles/secretmanager.secretVersionAdder",
          "members": [
            "principalSet://iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/cofhe-tee-keygen-pool/attribute.image_digest/sha256:1111111111111111111111111111111111111111111111111111111111111111"
          ]
        },
        {
          "role": "roles/secretmanager.viewer",
          "members": [
            "principalSet://iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/cofhe-tee-keygen-pool/attribute.image_digest/sha256:1111111111111111111111111111111111111111111111111111111111111111"
          ]
        }
      ]
    }
    EOT
  }
}

run "unconditional_bindings_pass" {
  command = plan
  override_data {
    target = data.google_secret_manager_secret_iam_policy.secret["s"]
    values = {
      policy_data = <<-EOT
      {
        "bindings": [
          {
            "role": "roles/secretmanager.secretVersionAdder",
            "members": [
              "principalSet://iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/cofhe-tee-keygen-pool/attribute.image_digest/sha256:1111111111111111111111111111111111111111111111111111111111111111"
            ]
          },
          {
            "role": "roles/secretmanager.viewer",
            "members": [
              "principalSet://iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/cofhe-tee-keygen-pool/attribute.image_digest/sha256:1111111111111111111111111111111111111111111111111111111111111111"
            ]
          }
        ]
      }
      EOT
    }
  }
  assert {
    condition     = output.SUCCESS.write_access_granted
    error_message = "a policy without conditions must pass"
  }
}

run "conditional_viewer_fails" {
  command = plan
  override_data {
    target = data.google_secret_manager_secret_iam_policy.secret["s"]
    values = {
      policy_data = <<-EOT
      {
        "bindings": [
          {
            "role": "roles/secretmanager.secretVersionAdder",
            "members": [
              "principalSet://iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/cofhe-tee-keygen-pool/attribute.image_digest/sha256:1111111111111111111111111111111111111111111111111111111111111111"
            ]
          },
          {
            "role": "roles/secretmanager.viewer",
            "members": [
              "principalSet://iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/cofhe-tee-keygen-pool/attribute.image_digest/sha256:1111111111111111111111111111111111111111111111111111111111111111"
            ],
            "condition": {
              "title": "deny",
              "expression": "false"
            }
          }
        ]
      }
      EOT
    }
  }
  expect_failures = [data.google_secret_manager_secret_iam_policy.secret["s"]]
}

run "conditional_adder_fails" {
  command = plan
  override_data {
    target = data.google_secret_manager_secret_iam_policy.secret["s"]
    values = {
      policy_data = <<-EOT
      {
        "bindings": [
          {
            "role": "roles/secretmanager.secretVersionAdder",
            "members": [
              "principalSet://iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/cofhe-tee-keygen-pool/attribute.image_digest/sha256:1111111111111111111111111111111111111111111111111111111111111111"
            ],
            "condition": {
              "title": "deny",
              "expression": "false"
            }
          },
          {
            "role": "roles/secretmanager.viewer",
            "members": [
              "principalSet://iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/cofhe-tee-keygen-pool/attribute.image_digest/sha256:1111111111111111111111111111111111111111111111111111111111111111"
            ]
          }
        ]
      }
      EOT
    }
  }
  expect_failures = [data.google_secret_manager_secret_iam_policy.secret["s"]]
}

run "conditional_reader_fails" {
  command = plan
  variables {
    grant_read_access  = true
    grant_reshare_read = true
  }
  override_data {
    target = data.google_iam_workload_identity_pool_provider.reader["keygen"]
    values = {
      name                = "projects/123/locations/global/workloadIdentityPools/cofhe-tee-reader-pool/providers/keygen-reader"
      disabled            = false
      attribute_condition = "attribute.hwmodel == \"GCP_INTEL_TDX\"\n&& attribute.swname == \"CONFIDENTIAL_SPACE\"\n&& (\",\" + attribute.support_attributes + \",\").contains(\",STABLE,\")\n&& attribute.dbgstat == \"disabled-since-boot\"\n&& attribute.gce_project_id == \"compute\"\n&& attribute.image_digest in [\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"]"
    }
  }
  override_data {
    target = data.google_secret_manager_secret_iam_policy.secret["s"]
    values = {
      policy_data = <<-EOT
      {
        "bindings": [
          {
            "role": "roles/secretmanager.secretVersionAdder",
            "members": [
              "principalSet://iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/cofhe-tee-keygen-pool/attribute.image_digest/sha256:1111111111111111111111111111111111111111111111111111111111111111"
            ]
          },
          {
            "role": "roles/secretmanager.viewer",
            "members": [
              "principalSet://iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/cofhe-tee-keygen-pool/attribute.image_digest/sha256:1111111111111111111111111111111111111111111111111111111111111111"
            ]
          },
          {
            "role": "roles/secretmanager.secretAccessor",
            "members": [
              "principalSet://iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/cofhe-tee-reader-pool/attribute.image_digest/sha256:1111111111111111111111111111111111111111111111111111111111111111"
            ],
            "condition": {
              "title": "deny",
              "expression": "false"
            }
          }
        ]
      }
      EOT
    }
  }
  expect_failures = [data.google_secret_manager_secret_iam_policy.secret["s"]]
}

# In CEL, && binds tighter than ||. A trailing "|| true" opens the gate to any
# Confidential Space token, but every pinned substring is still there.
run "write_gate_or_true_fails" {
  command = plan
  override_data {
    target = data.google_iam_workload_identity_pool_provider.write
    values = {
      name                = "projects/123/locations/global/workloadIdentityPools/cofhe-tee-keygen-pool/providers/cofhe-tee-keygen-provider"
      attribute_condition = "attribute.hwmodel == \"GCP_INTEL_TDX\"\n&& attribute.swname == \"CONFIDENTIAL_SPACE\"\n&& (\",\" + attribute.support_attributes + \",\").contains(\",STABLE,\")\n&& attribute.gce_project_id == \"compute\"\n&& attribute.image_digest == \"sha256:1111111111111111111111111111111111111111111111111111111111111111\" || true"
    }
  }
  expect_failures = [data.google_iam_workload_identity_pool_provider.write]
}

run "reader_gate_or_true_fails" {
  command = plan
  override_data {
    target = data.google_iam_workload_identity_pool_provider.reader["keygen"]
    values = {
      name                = "projects/123/locations/global/workloadIdentityPools/cofhe-tee-reader-pool/providers/keygen-reader"
      disabled            = true
      attribute_condition = "attribute.hwmodel == \"GCP_INTEL_TDX\"\n&& attribute.swname == \"CONFIDENTIAL_SPACE\"\n&& (\",\" + attribute.support_attributes + \",\").contains(\",STABLE,\")\n&& attribute.dbgstat == \"disabled-since-boot\"\n&& attribute.gce_project_id == \"compute\"\n&& attribute.image_digest in [\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"] || true"
    }
  }
  expect_failures = [data.google_iam_workload_identity_pool_provider.reader["keygen"]]
}

# Only the keygen write principal may add a version.
run "adder_held_by_consumer_fails" {
  command = plan
  override_data {
    target = data.google_secret_manager_secret_iam_policy.secret["s"]
    values = {
      policy_data = <<-EOT
      {
        "bindings": [
          {
            "role": "roles/secretmanager.secretVersionAdder",
            "members": [
              "principalSet://iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/cofhe-tee-reader-pool/attribute.image_digest/sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            ]
          },
          {
            "role": "roles/secretmanager.viewer",
            "members": [
              "principalSet://iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/cofhe-tee-keygen-pool/attribute.image_digest/sha256:1111111111111111111111111111111111111111111111111111111111111111"
            ]
          }
        ]
      }
      EOT
    }
  }
  expect_failures = [data.google_secret_manager_secret_iam_policy.secret["s"]]
}
