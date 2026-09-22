# Shared values for release v1.0.0. Rendered by .github/workflows/release.yml.
# Do not edit by hand — the next release overwrites this file.
#
# Your own project is NOT here. Pass it on the command line:
#   terraform apply -var-file=../values.tfvars -var partner_project_id=<your-project>

service_project_id = "fhenix-mainnet"

# Only this exact keygen image may WRITE your share. source_sha is the commit it
# was built from: your apply proves the pair against the public Sigstore log
# before it pins anything. The commit never enters the CEL.
image_digest = "sha256:78c1f33c60b1eb3a6d8ad657687c05708e44167b18bf599b08f4ab833a43519c"
source_sha   = "01652062b703ca19b11a9959155de9ae21697e21"

# Only these exact consumer images may READ your share — each on ONE secret.
attested_readers = {
  teecryptor = {
    gce_project_id = "fhenix-mainnet"
    image_digest   = "sha256:591d0046c306c5ce37c4c604d11b181de707698f2f9432648b16638912c49cfb"
    source_sha     = "c5168e102742a31e89ff8f1ca3bd7f98a8c466c9"
    secret_id      = "cofhe-tee-fhe-priv"
  }
  zee-k = {
    gce_project_id = "fhenix-mainnet"
    image_digest   = "sha256:291fcd710905cfc3b3ab1f0aa5a8fc062f6de9eb87a2f81674cfeab84bc5beec"
    source_sha     = "f3382f20f23a64ae479bc8dfa8eb10990dd20424"
    secret_id      = "cofhe-tee-zk-signer"
  }
}
