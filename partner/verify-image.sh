#!/usr/bin/env bash
# Prove that a Fhenix image digest was built by our public workflow, from a
# specific commit, BEFORE you pin it.
#
#   ./verify-image.sh <image> <digest> <commit>
#
#   image    keygen | teecryptor | zee-k
#   digest   sha256:<64 hex>   — the value you pin
#   commit   <40 hex>          — the commit we published beside that digest
#
# Exit 0 means the proof holds. Any other exit means DO NOT PIN.
#
# WHAT THIS PROVES. Our build signs each image with keyless Cosign. GitHub gives
# the job an OIDC token, Fulcio returns a short-lived certificate, and the
# signature goes into the PUBLIC Rekor transparency log. The certificate names
# the repository, the workflow file, the branch and the commit. This script
# asserts all four, plus the exact digest. A pass means: our workflow built this
# exact image from this exact commit.
#
# WHAT THIS DOES NOT PROVE. It does not say the commit is one you approve of.
# You choose which commits you trust, from our public history. This tool only
# ties a digest to a commit.
#
# WHOM YOU TRUST. Sigstore's public log, not Fhenix. The check needs no Fhenix
# credential and no GitHub account. Run it on any machine with network access.
#
# WHY THIS EXISTS. Your CEL pins the image digest. The attestation token carries
# no repository, workflow or commit claim, so the CEL cannot say where an image
# came from — only which one runs. This check fills that gap, at pin time.
#
# The values below are FIXED. They change only if we move a repository or rename
# a workflow, and then you get a new release of this repo. Per release you
# receive two values per image: the digest and the commit.

set -euo pipefail

OIDC_ISSUER="https://token.actions.githubusercontent.com"
REF="refs/heads/main"

# Terraform mode prints a JSON object on stdout, so every human line goes to
# stderr. Terraform shows stderr when the program fails.
TERRAFORM_MODE=false
if [ "${1:-}" = "--terraform" ]; then
  TERRAFORM_MODE=true
  shift
fi

say() {
  if [ "${TERRAFORM_MODE}" = true ]; then
    printf '%s\n' "$*" >&2
  else
    printf '%s\n' "$*"
  fi
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

usage() {
  die "usage: verify-image.sh <keygen|teecryptor|zee-k> sha256:<64 hex> <40 hex commit>"
}

# One entry per image. This is the whole constants map: you never type any of it.
# Written as a case rather than an associative array so it runs on the bash 3.2
# that macOS still ships.
image_constants() {
  case "$1" in
    keygen)
      REGISTRY="europe-west4-docker.pkg.dev/fhenix-artifacts-registry/cofhe-tee-keygen/keygen"
      REPO="FhenixProtocol/cofhe-tdx-keygen"
      WORKFLOW=".github/workflows/build-keygen-tdx.yml"
      ;;
    teecryptor)
      REGISTRY="europe-west4-docker.pkg.dev/fhenix-artifacts-registry/teecryptor/teecryptor"
      REPO="FhenixProtocol/teecryptor"
      WORKFLOW=".github/workflows/build-teecryptor.yml"
      ;;
    zee-k)
      REGISTRY="europe-west4-docker.pkg.dev/fhenix-artifacts-registry/zee-k-verifier/zee-k-verifier"
      REPO="FhenixProtocol/zee-k-verifier"
      WORKFLOW=".github/workflows/build-zk-verifier-tdx.yml"
      ;;
    *)
      return 1
      ;;
  esac
  IDENTITY="https://github.com/${REPO}/${WORKFLOW}@${REF}"
}

[ "$#" -eq 3 ] || usage
IMAGE="$1"
DIGEST="$2"
COMMIT="$3"

image_constants "${IMAGE}" || die "unknown image '${IMAGE}'. Use keygen, teecryptor or zee-k."

# Reject a malformed value here rather than passing it to cosign, which would
# report it as a missing signature and read like a failed proof.
case "${DIGEST}" in
  sha256:*) ;;
  *) die "digest must start with 'sha256:'. Got '${DIGEST}'." ;;
esac
printf '%s' "${DIGEST}" | grep -Eq '^sha256:[0-9a-f]{64}$' \
  || die "digest must be sha256: plus 64 lowercase hex characters. Got '${DIGEST}'."
printf '%s' "${COMMIT}" | grep -Eq '^[0-9a-f]{40}$' \
  || die "commit must be 40 lowercase hex characters (the full SHA, not the short one). Got '${COMMIT}'."

command -v cosign >/dev/null 2>&1 || die "cosign is not installed. See PARTNER_GUIDE.md, step 1."

say "Verifying ${IMAGE}"
say "  image   ${REGISTRY}@${DIGEST}"
say "  commit  ${COMMIT}"
say "  built by ${IDENTITY}"
say ""

# Every flag below is an assertion. cosign exits non-zero if any one of them
# does not match the certificate in the public log.
#   --certificate-github-workflow-sha is the one that pins the exact commit.
if output="$(cosign verify "${REGISTRY}@${DIGEST}" \
      --certificate-oidc-issuer "${OIDC_ISSUER}" \
      --certificate-identity "${IDENTITY}" \
      --certificate-github-workflow-repository "${REPO}" \
      --certificate-github-workflow-ref "${REF}" \
      --certificate-github-workflow-sha "${COMMIT}" 2>&1)"; then
  say "PASS — our workflow built this digest from commit ${COMMIT}."
  say "You may pin it."
  if [ "${TERRAFORM_MODE}" = true ]; then
    printf '{"verified":"true","image":"%s","digest":"%s","commit":"%s"}\n' \
      "${IMAGE}" "${DIGEST}" "${COMMIT}"
  fi
  exit 0
fi

printf '%s\n' "" >&2
printf '%s\n' "FAIL — the proof does not hold for ${IMAGE}. DO NOT PIN THIS DIGEST." >&2
printf '%s\n' "" >&2
printf '%s\n' "${output}" >&2
printf '%s\n' "" >&2
printf '%s\n' "What this means, most likely first:" >&2
printf '%s\n' "  - the digest and the commit do not belong together" >&2
printf '%s\n' "  - one of the two values was mistyped or truncated" >&2
printf '%s\n' "  - the image was not built by our public workflow" >&2
printf '%s\n' "" >&2
printf '%s\n' "Change nothing. Send this output to Fhenix." >&2
exit 1
