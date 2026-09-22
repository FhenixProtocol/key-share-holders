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
# A pass means this: our workflow, on main, built this exact image from this
# exact commit. It does NOT mean the commit is one you approve of. You choose
# which of our commits you trust.
#
# The release tag carries the signed proof for each digest it pins, in ./bundles,
# so a normal run calls no GitHub API. Set FHENIX_IGNORE_SHIPPED_BUNDLE=1 to
# download the proof from GitHub instead and compare.
#
# The constants below are FIXED. You never type any of them. Per release you
# receive two values for each image: the digest and the commit.
#
# PARTNER_GUIDE.md explains why this is safe when we are the ones who give you
# the file. Keep that explanation there, not here.

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

command -v gh >/dev/null 2>&1 \
  || die "gh is not installed. See PARTNER_GUIDE.md, step 1."

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
  # Checked here, not at the top: a normal apply reads a shipped file and needs
  # neither of these. The guide says the same, so the two must agree.
  for tool in jq curl; do
    command -v "${tool}" >/dev/null 2>&1 \
      || die "${tool} is not installed, and this digest needs the fallback to api.github.com. See PARTNER_GUIDE.md, step 1."
  done

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
    elif [ "${http}" = "401" ]; then
      printf '%s\n' "api.github.com refused the credentials in FHENIX_PROVENANCE_TOKEN." >&2
      printf '%s\n' "That token is optional. Unset it and run this again:" >&2
      printf '%s\n' "  unset FHENIX_PROVENANCE_TOKEN" >&2
    else
      printf '%s\n' "api.github.com answered with an error. Wait, then try again." >&2
    fi
    printf '%s\n' "" >&2
    printf '%s\n' "Nothing was written. Do not pin this digest until a check passes." >&2
    printf '%s\n' "Send this output to Fhenix if it does not clear." >&2
    exit 1
  fi

  # EVERY bundle, as JSON Lines, not just the first. The API may return several
  # attestations for one digest, and gh picks the one that satisfies the flags.
  # Taking [0] blindly would turn "wrong element" into "the proof does not hold".
  jq -ce '.attestations[].bundle' < "${response}" > "${bundle}" \
    || die "the attestation response was not in the expected form. Send this to Fhenix."
}

# The release tag ships the signed attestation for every digest it pins, so the
# usual path reaches no GitHub API. The file name carries the digest. A file
# from another release can thus never replace this one: either the exact file is
# here, or we fetch.
#
# FHENIX_IGNORE_SHIPPED_BUNDLE makes this download instead. Set it to compare
# what we gave you against what GitHub serves. We document it because the claim
# "our copy is checked as hard as yours" is worth more if you can test it.
shipped="${SCRIPT_DIR}/bundles/${IMAGE}-${DIGEST#sha256:}.jsonl"
if [ -n "${FHENIX_IGNORE_SHIPPED_BUNDLE:-}" ]; then
  BUNDLE_SOURCE=api
  say "  proof   api.github.com (FHENIX_IGNORE_SHIPPED_BUNDLE is set)"
  fetch_bundle_from_api
elif [ -s "${shipped}" ]; then
  BUNDLE_SOURCE=shipped
  cp "${shipped}" "${bundle}"
  say "  proof   bundles/${IMAGE}-${DIGEST#sha256:}.jsonl (shipped in this release)"
elif [ -e "${shipped}" ]; then
  # Present but empty. Saying "ships no bundle" here would be untrue, and it
  # would send the partner to look for a network problem they do not have.
  die "the file bundles/${IMAGE}-${DIGEST#sha256:}.jsonl is empty. It is damaged. Get the release tag again."
else
  BUNDLE_SOURCE=api
  say "  proof   api.github.com (this release ships no file for this digest)"
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
  # attestation that passed. Partners never set this. The path is relative to the
  # working directory of the caller, and release.yml runs from the repo root.
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

# ONLY these mean the proof did not hold. An ALLOW-list on purpose: gh also
# fetches the image manifest and two trust roots, and a deny-list of those
# failures always has a hole. A hole tells a partner their image is bad when
# their network is bad.
#
# So match only what gh's own checks produce. A general phrase such as "does not
# match" also appears in a registry mismatch, an x509 error and a TUF rollover.
#   expected SourceRepository...  the repository, the branch or the commit
#   expected Issuer to be         the certificate came from another OIDC issuer
#   verifying with issuer         gh's catch-all: signature, identity or subject
#   bundle issuer                 the leaf certificate is not from a known CA
#   no attestations               nothing in the bundle carries the right claim
#
# A later gh could reword one of these, and a real failure would then read as
# "could not check". That direction is safe, because the exit code is 1 either
# way. Do NOT answer a reworded string by adding a deny-list.
if printf '%s' "${output}" | grep -qE \
  'expected SourceRepository|expected Issuer to be|verifying with issuer|bundle issuer|no attestations'; then
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
    printf '%s\n' "  - the file in bundles/ changed after this release was tagged" >&2
  fi
  printf '%s\n' "" >&2
  printf '%s\n' "Change nothing. Send this output to Fhenix." >&2
  exit 1
fi

printf '%s\n' "" >&2
printf '%s\n' "COULD NOT CHECK — the check did not finish." >&2
printf '%s\n' "This is NOT a failed proof. It is also NOT a pass." >&2
printf '%s\n' "" >&2
printf '%s\n' "${output}" >&2
printf '%s\n' "" >&2
printf '%s\n' "The usual causes:" >&2
printf '%s\n' "  - the image registry could not be reached" >&2
printf '%s\n' "  - a public trust root could not be reached:" >&2
printf '%s\n' "    tuf-repo-cdn.sigstore.dev or tuf-repo.github.com" >&2
if [ "${BUNDLE_SOURCE}" = shipped ]; then
  printf '%s\n' "  - the file in bundles/ is damaged. Get the tag again." >&2
fi
printf '%s\n' "" >&2
printf '%s\n' "Check the network, a proxy, or a firewall rule. See PARTNER_GUIDE.md," >&2
printf '%s\n' "step 1. Then run the same command again." >&2
printf '%s\n' "" >&2
printf '%s\n' "Nothing was written. Do not pin this digest until a check passes." >&2
printf '%s\n' "Send this output to Fhenix if it does not clear." >&2
exit 1
