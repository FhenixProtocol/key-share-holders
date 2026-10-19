# Shared values for release v1.0.5. Rendered by .github/workflows/release.yml.
# Do not edit by hand. The next release overwrites this file.
#
# Your own project is NOT here. Pass it on the command line:
#   terraform apply -var-file=../values.tfvars -var partner_project_id=<your-project>

service_project_id = "fhenix-mainnet"

# Only this exact keygen image may WRITE your share. source_sha is the commit it
# was built from: your apply proves the pair against the public Sigstore log
# before it pins anything. The commit never enters the CEL.
image_digest = "sha256:f2ea9c4802236eb0f3f3c42c8c5c6d8f02e062d136f8ac06ef7f34ac64688f69"
source_sha   = "7f93823f135f47b794482b984870b42aef95468d"

# Only these exact consumer images may READ your share, each on ONE secret.
attested_readers = {
  teecryptor = {
    gce_project_id = "fhenix-mainnet"
    image_digest   = "sha256:ae85f4d29ea0def0a6748bf75cf319e2236d9800c9fb5b22de5d09319dc79624"
    source_sha     = "6dd84e784d359cbe81db9cc0a4ecb5b5d28e722d"
    secret_id      = "cofhe-tee-fhe-priv"
  }
  zee-k = {
    gce_project_id = "fhenix-mainnet"
    image_digest   = "sha256:88f5a66d658f207b5b503a0b5803c183aca076999d9ed423d974f58bfcee1969"
    source_sha     = "fe559a98cb2ac8c48c612d54985436f6bf981ea0"
    secret_id      = "cofhe-tee-zk-signer"
  }
}
