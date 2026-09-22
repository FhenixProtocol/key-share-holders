# Provenance gate — no resources, only checks.
#
# Every image digest this apply pins is checked against the PUBLIC Sigstore
# transparency log first. The check asks one question: did the Fhenix workflow
# named in verify-image.sh build this exact digest from this exact commit?
#
# A failed check fails `terraform plan` AND `terraform apply`, before any IAM is
# written. That is the point: no digest reaches your gates without the proof.
# You cannot forget to run it, and a `-target` cannot route around it.
#
# You can run the same check by hand:
#   ./verify-image.sh keygen <digest> <commit>
#
# This needs `gh`, `jq` and `curl` on the machine that runs terraform, plus
# network access to api.github.com and the image registry. No GitHub account is
# required. See PARTNER_GUIDE.md step 1.
#
# NOTE: the commit stops here. It is proof material only. The CEL pins the
# digest and nothing else, so `source_sha` is never passed into the onboarding
# module. See the comment on `attested_readers` in main.tf.

locals {
  # image key => the two values that change per release. Keys match the ones in
  # verify-image.sh: keygen, teecryptor, zee-k.
  #
  # An empty image_digest means the keygen write gate is unpinned (early dev),
  # so there is no digest to prove and that check is skipped.
  all_pinned_images = merge(
    var.image_digest == "" ? {} : {
      keygen = {
        digest = var.image_digest
        commit = var.source_sha
      }
    },
    {
      for k, r in var.attested_readers : k => {
        digest = r.image_digest
        commit = r.source_sha
      }
    },
  )

  # Prove a digest exactly when this apply GRANTS something to it. That keeps two
  # properties at once:
  #
  #  - Nothing is ever granted to an unproven image. The keygen digest is proven
  #    whenever the write binding is created, and each reader digest whenever its
  #    secretAccessor binding is created.
  #  - The emergency brake works offline. `grant_read_access = false` with write
  #    already frozen grants nothing, so it needs no check and no network.
  #
  # A CEL that pins an unproven digest but has no binding grants nothing, which is
  # why gating on the grant flags is enough.
  pinned_images = merge(
    var.grant_write_access ? { for k, v in local.all_pinned_images : k => v if k == "keygen" } : {},
    var.grant_read_access ? { for k, v in local.all_pinned_images : k => v if k != "keygen" } : {},
  )
}

data "external" "provenance" {
  for_each = local.pinned_images

  # Values are passed as arguments, not as a `query` on stdin, so the script
  # needs no JSON parser and stays runnable by hand.
  program = [
    "bash",
    "${path.module}/verify-image.sh",
    "--terraform",
    each.key,
    each.value.digest,
    each.value.commit,
  ]

  lifecycle {
    postcondition {
      condition     = self.result.verified == "true"
      error_message = "CHECK FAILED: the provenance check returned without proving ${each.key}. Do not change anything. Send this message to Fhenix."
    }
  }
}

output "provenance_verified" {
  description = "Each pinned image, with the commit its digest was proven to come from. Printed only when every check passed."
  value = {
    for k, d in data.external.provenance : k => {
      digest = d.result.digest
      commit = d.result.commit
    }
  }
}
