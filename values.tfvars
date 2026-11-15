# Shared values for release v1.0.8. Rendered by .github/workflows/release.yml.
# Do not edit by hand. The next release overwrites this file.
#
# Your own project is NOT here. Pass it on the command line:
#   terraform apply -var-file=../values.tfvars -var partner_project_id=<your-project>

service_project_id = "fhenix-mainnet"

# Only this exact keygen image may WRITE your share. source_sha is the commit it
# was built from: your apply proves the pair against the public Sigstore log
# before it pins anything. The commit never enters the CEL.
image_digest = "sha256:781096676f8f7ad690e50b6cc58974b00f581d7f168e46bfb0d7a65a087fcc35"
source_sha   = "4a816b9090ded5ef8f6be75cb067fc7c20c7a9dc"

# Only these exact consumer images may READ your share, each on ONE secret. The
# first image is this release's. A second one, marked "previous", is the previous
# release's, kept while an upgrade is in progress.
attested_readers = {
  teecryptor = {
    gce_project_id = "fhenix-mainnet"
    secret_id      = "cofhe-tee-fhe-priv"
    images = [
      { image_digest = "sha256:69e26a0c6300e32878e1ab735592d357c7bcfdc978cff3206a5d3840d945179a", source_sha = "7099fc89bb8ac423aca281c23a32b1ac5acca371" },
    ]
  }
  zee-k = {
    gce_project_id = "fhenix-mainnet"
    secret_id      = "cofhe-tee-zk-signer"
    images = [
      { image_digest = "sha256:7f757e6abcd4ff49e0c67e825505d2cd9f019f1a6a8649fc7a0257c5b9113fe1", source_sha = "91d81d3df5618a01106c2f345a6fa1eab91cc0de" },
    ]
  }
}
