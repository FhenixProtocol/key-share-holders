# Shared values for release v1.2.0. Rendered by .github/workflows/release.yml.
# Do not edit by hand — the next release overwrites this file.
#
# Your own project is NOT here. Pass it on the command line:
#   terraform apply -var-file=../values.tfvars -var partner_project_id=<your-project>

service_project_id = "fhenix-compute-project"

# Only this exact keygen image may WRITE your share. source_sha is the commit it
# was built from: your apply proves the pair against the public Sigstore log
# before it pins anything. The commit never enters the CEL.
image_digest = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
source_sha   = "1111111111111111111111111111111111111111"

# Not a ceremony release: write access stays frozen (module default).

# Only these exact consumer images may READ your share — each on ONE secret.
attested_readers = {
  teecryptor = {
    gce_project_id = "fhenix-compute-project"
    image_digest   = "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    source_sha     = "2222222222222222222222222222222222222222"
    secret_id      = "cofhe-tee-fhe-priv"
  }
  zee-k = {
    gce_project_id = "fhenix-compute-project"
    image_digest   = "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
    source_sha     = "3333333333333333333333333333333333333333"
    secret_id      = "cofhe-tee-zk-signer"
  }
}
