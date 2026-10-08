# Shared values for release v1.0.4. Rendered by .github/workflows/release.yml.
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
    image_digest   = "sha256:bf5114a6fe877dbd18d734aeed53c3faee93192f9b7256c5d6e23e1659da63a2"
    source_sha     = "ffba731ab6162ef9eef471c1abbe6a124b998c06"
    secret_id      = "cofhe-tee-fhe-priv"
  }
  zee-k = {
    gce_project_id = "fhenix-mainnet"
    image_digest   = "sha256:84591341cea631ec200df493b96f4e4797986f65e43f9d7ed2f5c9d10c5b5d09"
    source_sha     = "cc3e1d633d6f1231032dd68c22a5f8295c810069"
    secret_id      = "cofhe-tee-zk-signer"
  }
}
