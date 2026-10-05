# Shared values for release v1.0.3. Rendered by .github/workflows/release.yml.
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
    image_digest   = "sha256:c111fb96307039eea5ff0d3aa808f0146392c099c48bd417b8ac323bd566cbd9"
    source_sha     = "852f1160857ae5a81a41df546199156011fe6436"
    secret_id      = "cofhe-tee-fhe-priv"
  }
  zee-k = {
    gce_project_id = "fhenix-mainnet"
    image_digest   = "sha256:75265b62e9bc90c7fc4c3ff0b03ba714aefece3796d55fe9c9af7bfaa95a5b2b"
    source_sha     = "ad2e30c3f10a4d1c9992d17a4e2d122ab56b272c"
    secret_id      = "cofhe-tee-zk-signer"
  }
}
