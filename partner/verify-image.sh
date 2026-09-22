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
# WHAT THIS PROVES. Our build emits a SLSA build provenance attestation. GitHub
# gives the job a short-lived identity, Fulcio issues a certificate, and the
# result is recorded in the PUBLIC Sigstore transparency log. The certificate
# names the repository, the workflow file, the branch and the commit. This
# script asserts all four, plus the exact digest. A pass means: our workflow, on
# main, built this exact image from this exact commit.
#
# WHAT THIS DOES NOT PROVE. It does not say the commit is one you approve of.
# You choose which commits you trust, from our public history. This tool only
# ties a digest to a commit.
#
# The values below are FIXED. They change only if we move a repository or rename
# a workflow, and then you get a new release of this repo. Per release you
# receive two values per image: the digest and the commit.
#
# WHERE THE PROOF COMES FROM. The release tag carries the signed attestation for
# each digest it pins, in ./bundles. This script uses that copy, so a normal
# apply does not call api.github.com at all. Shipping the bundle grants us
# nothing: `gh` checks its signature, the certificate identity and the subject
# digest against Sigstore's PUBLIC trust root, so our copy is checked exactly as
# hard as one you download. If no shipped bundle matches the digest you asked
# about, the script falls back to the public GitHub API.

set -euo pipefail

REF="refs/heads/main"

# The bundles ship beside this script, so the path follows the script and not
# the caller's working directory. Terraform runs it from partner/.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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
  SIGNER_WORKFLOW="${REPO}/${WORKFLOW}"
}

[ "$#" -eq 3 ] || usage
IMAGE="$1"
DIGEST="$2"
COMMIT="$3"

image_constants "${IMAGE}" \
  || die "unknown image '${IMAGE}'. Use keygen, teecryptor or zee-k. If a Fhenix release added a consumer, this script is the copy that needs updating."

# Reject a malformed value here rather than passing it on, where it would be
# reported as a missing attestation and read like a failed proof.
case "${DIGEST}" in
  sha256:*) ;;
  *) die "digest must start with 'sha256:'. Got '${DIGEST}'." ;;
esac
printf '%s' "${DIGEST}" | grep -Eq '^sha256:[0-9a-f]{64}$' \
  || die "digest must be sha256: plus 64 lowercase hex characters. Got '${DIGEST}'."
printf '%s' "${COMMIT}" | grep -Eq '^[0-9a-f]{40}$' \
  || die "commit must be 40 lowercase hex characters (the full SHA, not the short one). Got '${COMMIT}'."

for tool in gh jq curl; do
  command -v "${tool}" >/dev/null 2>&1 \
    || die "${tool} is not installed. See PARTNER_GUIDE.md, step 1."
done

# --source-ref and --source-digest arrived in gh 2.68.0. An older gh exits with
# "unknown flag", which this script would otherwise report as a failed proof.
# Name the real problem instead.
gh_version="$( { gh --version 2>/dev/null || true; } | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
gh_major="${gh_version%%.*}"
gh_rest="${gh_version#*.}"
gh_minor="${gh_rest%%.*}"
if [ -z "${gh_version}" ] \
  || [ "${gh_major}" -lt 2 ] \
  || { [ "${gh_major}" -eq 2 ] && [ "${gh_minor}" -lt 68 ]; }; then
  die "gh ${gh_version:-(unknown)} is too old. This check needs gh 2.68 or later, which is where --source-digest was added. Upgrade gh, then run this again."
fi

say "Verifying ${IMAGE}"
say "  image   ${REGISTRY}@${DIGEST}"
say "  commit  ${COMMIT}"
say "  built by ${SIGNER_WORKFLOW}@${REF}"

# `gh attestation verify` rejects a bundle whose filename does not end in
# .json or .jsonl, so this cannot be a bare mktemp file.
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT
bundle="${workdir}/bundle.jsonl"
response="${workdir}/response.json"

# gh resolves the image through the DEFAULT DOCKER KEYCHAIN. A partner who has
# ever run `gcloud auth configure-docker` has a credential helper in
# ~/.docker/config.json, and a stale token there makes gh fail before it checks
# anything — which this script would report as a failed proof. Point gh at an
# empty config so the image is always fetched anonymously, which is what the
# public registry allows anyway.
mkdir -p "${workdir}/docker"
export DOCKER_CONFIG="${workdir}/docker"

# Used only when the release ships no bundle for this digest.
fetch_bundle_from_api() {
  # Fetched anonymously. This endpoint needs no GitHub account, which is what
  # keeps the check independent of any credential we could hand you.
  #
  # Optional, and never required. It only raises the anonymous limit of 60 requests
  # an hour per IP address, which a shared office network can exhaust.
  #
  # Deliberately NOT GITHUB_TOKEN or GH_TOKEN: those are commonly exported on a
  # developer machine, and an expired one would turn a working check into a
  # permanent 401 with advice that never helps.
  auth=()
  if [ -n "${FHENIX_PROVENANCE_TOKEN:-}" ]; then
    auth=(-H "Authorization: Bearer ${FHENIX_PROVENANCE_TOKEN}")
  fi
  # ${auth[@]+...} because bash 3.2 errors on an empty array under `set -u`.
  http="$(curl -sS -w '%{http_code}' -o "${response}" \
    ${auth[@]+"${auth[@]}"} \
    "https://api.github.com/repos/${REPO}/attestations/${DIGEST}" || true)"

  if [ "${http}" = "404" ]; then
    printf '%s\n' "" >&2
    printf '%s\n' "FAIL — no attestation is published for this digest." >&2
    printf '%s\n' "DO NOT PIN THIS DIGEST." >&2
    printf '%s\n' "" >&2
    printf '%s\n' "This usually means one of:" >&2
    printf '%s\n' "  - the digest was mistyped or truncated" >&2
    printf '%s\n' "  - the image predates build provenance, or is a development build" >&2
    printf '%s\n' "  - the image was not built by our public workflow" >&2
    printf '%s\n' "" >&2
    printf '%s\n' "Change nothing. Send this output to Fhenix." >&2
    exit 1
  fi

  # Anything else is OUR side or YOUR network, not a statement about the image.
  # The anonymous API allows 60 requests an hour per IP address, and a plan spends
  # one per pinned image, so a shared office address can reach 403 honestly.
  if [ "${http}" != "200" ]; then
    printf '%s\n' "" >&2
    printf '%s\n' "COULD NOT CHECK — this is NOT a failed proof (HTTP ${http})." >&2
    printf '%s\n' "" >&2
    if [ "${http}" = "403" ] || [ "${http}" = "429" ]; then
      printf '%s\n' "GitHub is rate-limiting this address. The anonymous limit is 60" >&2
      printf '%s\n' "requests an hour per IP, and it is shared by everyone behind your" >&2
      printf '%s\n' "network address. Wait, then run the same command again, or set" >&2
      printf '%s\n' "FHENIX_PROVENANCE_TOKEN to any GitHub token to raise the limit." >&2
    elif [ "${http}" = "000" ]; then
      printf '%s\n' "api.github.com could not be reached at all. Check the network, a" >&2
      printf '%s\n' "proxy, or a firewall rule. See PARTNER_GUIDE.md, step 1." >&2
    else
      printf '%s\n' "api.github.com answered with an error. Wait, then try again." >&2
    fi
    printf '%s\n' "" >&2
    printf '%s\n' "Nothing was written. The image is neither proven nor disproven." >&2
    printf '%s\n' "Tell Fhenix only if it keeps happening." >&2
    exit 1
  fi

  # EVERY bundle, as JSON Lines, not just the first. The API may return several
  # attestations for one digest, and gh picks the one that satisfies the flags.
  # Taking [0] blindly would turn "wrong element" into "the proof does not hold".
  jq -ce '.attestations[].bundle' < "${response}" > "${bundle}" \
    || die "the attestation response was not in the expected form. Send this to Fhenix."
}

# The release tag ships the signed attestation for every digest it pins, so the
# usual path reaches no GitHub API. The file name carries the digest, so a
# bundle from another release can never stand in for this one: either the exact
# file is here, or we fetch.
shipped="${SCRIPT_DIR}/bundles/${IMAGE}-${DIGEST#sha256:}.jsonl"
if [ -s "${shipped}" ]; then
  BUNDLE_SOURCE=shipped
  cp "${shipped}" "${bundle}"
  say "  proof   bundles/${IMAGE}-${DIGEST#sha256:}.jsonl (shipped in this release)"
else
  BUNDLE_SOURCE=api
  say "  proof   api.github.com (this release ships no bundle for this digest)"
  fetch_bundle_from_api
fi
say ""

# Every flag below is an assertion. gh exits non-zero if any one of them does
# not match the certificate in the attestation.
#   --source-digest is the one that pins the exact commit.
#   --source-ref and --signer-workflow are FIXED here, not read from the
#   attestation, so an image built from another branch cannot satisfy them.
if output="$(gh attestation verify "oci://${REGISTRY}@${DIGEST}" \
      --bundle "${bundle}" \
      --repo "${REPO}" \
      --signer-workflow "${SIGNER_WORKFLOW}" \
      --source-ref "${REF}" \
      --source-digest "${COMMIT}" 2>&1)"; then
  say "PASS — our workflow built this digest from commit ${COMMIT}."
  say "You may pin it."
  # Fhenix release tooling only: release.yml proves each pin, then commits the
  # very bundle that passed. Partners never set this.
  if [ -n "${FHENIX_BUNDLE_OUT:-}" ] && [ "${BUNDLE_SOURCE}" = api ]; then
    mkdir -p "${FHENIX_BUNDLE_OUT}"
    cp "${bundle}" "${FHENIX_BUNDLE_OUT}/${IMAGE}-${DIGEST#sha256:}.jsonl"
  fi
  if [ "${TERRAFORM_MODE}" = true ]; then
    printf '{"verified":"true","image":"%s","digest":"%s","commit":"%s"}\n' \
      "${IMAGE}" "${DIGEST}" "${COMMIT}"
  fi
  exit 0
fi

# gh does two more network operations: it fetches the image manifest from the
# registry, and Sigstore's trust root. A failure in either says nothing about the
# image, so it must not be reported as a failed proof. A genuine proof failure
# names a certificate field instead, and matches none of these.
if printf '%s' "${output}" | grep -qE \
  'failed to fetch remote image|error getting credentials|denied access to the requested resource|MANIFEST_UNKNOWN|UNAUTHORIZED|DENIED|TUF|trusted root|connection refused|no such host|i/o timeout|context deadline exceeded|tls:'; then
  printf '%s\n' "" >&2
  printf '%s\n' "COULD NOT CHECK — this is NOT a failed proof." >&2
  printf '%s\n' "" >&2
  printf '%s\n' "${output}" >&2
  printf '%s\n' "" >&2
  printf '%s\n' "Something in the path could not be reached: the image registry, or" >&2
  printf '%s\n' "Sigstore's trust root. Check the network, a proxy, or a firewall rule." >&2
  printf '%s\n' "See PARTNER_GUIDE.md, step 1." >&2
  printf '%s\n' "" >&2
  printf '%s\n' "Nothing was written. The image is neither proven nor disproven." >&2
  printf '%s\n' "Tell Fhenix only if it keeps happening." >&2
  exit 1
fi

printf '%s\n' "" >&2
printf '%s\n' "FAIL — the proof does not hold for ${IMAGE}. DO NOT PIN THIS DIGEST." >&2
printf '%s\n' "" >&2
printf '%s\n' "${output}" >&2
printf '%s\n' "" >&2
printf '%s\n' "What this means, most likely first:" >&2
printf '%s\n' "  - the digest and the commit do not belong together" >&2
printf '%s\n' "  - one of the two values was mistyped or truncated" >&2
printf '%s\n' "  - the image was not built on main by our public workflow" >&2
if [ "${BUNDLE_SOURCE}" = shipped ]; then
  printf '%s\n' "  - the bundle in bundles/ changed after this release was tagged" >&2
fi
printf '%s\n' "" >&2
printf '%s\n' "Change nothing. Send this output to Fhenix." >&2
exit 1
