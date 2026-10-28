# Test fixture: a release in the image-list shape. Not a real release.
#
# Your own project is NOT here. Pass it on the command line:
#   terraform apply -var-file=../values.tfvars -var partner_project_id=<your-project>

service_project_id = "fhenix-mainnet"

# Only this exact keygen image may WRITE your share. source_sha is the commit it
# was built from: your apply proves the pair against the public Sigstore log
# before it pins anything. The commit never enters the CEL.
image_digest = "sha256:f2ea9c4802236eb0f3f3c42c8c5c6d8f02e062d136f8ac06ef7f34ac64688f69"
source_sha   = "7f93823f135f47b794482b984870b42aef95468d"

# Only these exact consumer images may READ your share, each on ONE secret. The
# first image is this release's; a second one is the previous release's, kept
# while an upgrade is in progress.
attested_readers = {
  teecryptor = {
    gce_project_id = "fhenix-mainnet"
    secret_id      = "cofhe-tee-fhe-priv"
    images = [
      { image_digest = "sha256:1111111111111111111111111111111111111111111111111111111111111111", source_sha = "2222222222222222222222222222222222222222" },
      { image_digest = "sha256:bf5114a6fe877dbd18d734aeed53c3faee93192f9b7256c5d6e23e1659da63a2", source_sha = "ffba731ab6162ef9eef471c1abbe6a124b998c06" }, # previous
    ]
  }
  zee-k = {
    gce_project_id = "fhenix-mainnet"
    secret_id      = "cofhe-tee-zk-signer"
    images = [
      { image_digest = "sha256:3333333333333333333333333333333333333333333333333333333333333333", source_sha = "4444444444444444444444444444444444444444" },
    ]
  }
}
