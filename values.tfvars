# Shared values for release v1.0.6. Rendered by .github/workflows/release.yml.
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
    image_digest   = "sha256:e773b9cc9f72dc87906d05c6f8e96ac8e8dd7480db3d6e66f3b3b20d58ea8ad4"
    source_sha     = "47a59438caa7390582d4c470df7a02c42fa21d85"
    secret_id      = "cofhe-tee-zk-signer"
  }
}
