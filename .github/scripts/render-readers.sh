#!/usr/bin/env bash
# Resolve every pin of a release and render values.tfvars and EXPECTED.md.
# release.yml runs it, and CI runs it on the fixtures, so both run one code path.
# An empty input carries the previous release's pair. An unchanged image is not
# retyped: retyping is how a digest and its commit drift apart, and the previous
# tag already holds the proven pair.
#
#   render-readers.sh <out_dir>
#
# Environment, every name required (an input may be empty):
#   TAG, COMPUTE_PROJECT
#   KEEP_PREVIOUS_READERS          true | false
#   IN_{KEYGEN,TEECRYPTOR,ZEEK}_{DIGEST,SHA}   empty = carry from the previous release
#   PREV_TAG, PREV_FILE            both empty for the first release
#
# <out_dir> gets values.tfvars, EXPECTED.md, pairs.md (the pair table) and
# pairs ("<image> <digest> <sha>" per pinned pair, for the proof step).
set -euo pipefail

out="$1"
here="$(cd "$(dirname "$0")" && pwd)"
tmpl="$here/../release-templates"
summary="${GITHUB_STEP_SUMMARY:-/dev/null}"
: "${TAG:?}" "${COMPUTE_PROJECT:?}"
: "${IN_KEYGEN_DIGEST?}" "${IN_KEYGEN_SHA?}" "${IN_TEECRYPTOR_DIGEST?}" "${IN_TEECRYPTOR_SHA?}"
: "${IN_ZEEK_DIGEST?}" "${IN_ZEEK_SHA?}" "${PREV_TAG?}" "${PREV_FILE?}"

die() { echo "::error::$*" >&2; exit 1; }

case "${KEEP_PREVIOUS_READERS:-}" in
  true | false) ;;
  *) die "keep_previous_readers must be true or false, got '${KEEP_PREVIOUS_READERS:-}'" ;;
esac
keep="$KEEP_PREVIOUS_READERS"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
: > "$work/prev.pins"
if [[ -n "$PREV_FILE" ]]; then
  awk -f "$here/pins.awk" "$PREV_FILE" > "$work/prev.pins"
fi
lookup() { awk -v k="$1" '$1 == k { print $2 }' "$work/prev.pins"; }

# FIRST-LIST-RELEASE
# The first list release must carry each reader's live digest: dropping it there
# cuts every running consumer off its share before the new image is proven live.
if [[ "$keep" == false && "$(lookup shape)" == flat ]]; then
  die "the previous release uses one digest per reader; keep it once (keep_previous_readers=true)"
fi

check() {  # label, digest, sha
  [[ "$2" =~ ^sha256:[0-9a-f]{64}$ ]] || die "$1 is not a canonical digest: '$2'"
  # The partner proves digest and commit together; a short sha never matches.
  [[ "$3" =~ ^[0-9a-f]{40}$ ]] || die "$1 commit is not a full 40-hex sha: '$3'"
}

# Sets D, S and ORIGIN.
resolve() {  # label, digest key, sha key, supplied digest, supplied sha
  # Half a pair is almost always a half-filled form. Carrying the old commit next
  # to a new digest fails later as "the proof does not hold", which reads like a
  # compromised image rather than a typo.
  if [[ -n "$4" && -z "$5" ]] || [[ -z "$4" && -n "$5" ]]; then
    die "fill both the digest and the commit for $1, or leave both empty to carry the pair forward."
  fi
  if [[ -n "$4" ]]; then
    D="$4" S="$5" ORIGIN="supplied"
  else
    D="$(lookup "$2")" S="$(lookup "$3")" ORIGIN="carried from $PREV_TAG"
    if [[ -z "$D" || -z "$S" ]]; then
      if [[ -n "$PREV_TAG" ]]; then
        die "$1 is empty, and $PREV_TAG does not carry it. Fill it in."
      fi
      die "$1 is empty and there is no previous release to carry it from. Fill it in."
    fi
  fi
  check "$1" "$D" "$S"
}

{
  echo "| Image | Digest | Source commit | Source |"
  echo "|---|---|---|---|"
} >> "$summary"
: > "$out/pairs"
printf '%s\n' "| Image | Digest | Source commit |" "|---|---|---|" > "$out/pairs.md"
row() {  # label, digest, sha, image, origin
  echo "| $1 | \`$2\` | \`$3\` |" >> "$out/pairs.md"
  echo "| $1 | \`$2\` | \`$3\` | $5 |" >> "$summary"
  echo "$4 $2 $3" >> "$out/pairs"
}

resolve keygen keygen keygen-sha "$IN_KEYGEN_DIGEST" "$IN_KEYGEN_SHA"
KEYGEN_DIGEST="$D" KEYGEN_SHA="$S"
row "keygen (write gate)" "$D" "$S" keygen "$ORIGIN"

# The new pair is index 0. With keep, one previous image follows it: index 1 if
# the previous release lists 2, else index 0. Index 1 is the older image of an
# open overlap, and it still runs until a tag B retires it. With keep and no new
# digest, the previous list carries unchanged: a release that only moves another
# image must not end an upgrade overlap. Only these two previous images are
# looked at, so a reader never lists more than 2, and a digest never twice.
reader() {  # image, supplied digest, supplied sha
  local r="$1" pd ps
  resolve "$r" "$r.0" "$r-sha.0" "$2" "$3"
  echo "      { image_digest = \"$D\", source_sha = \"$S\" }," > "$work/$r.images"
  echo "              + \"$D\"," > "$work/$r.gates"
  row "$r" "$D" "$S" "$r" "$ORIGIN"
  [[ "$keep" == true ]] || return 0
  pd="$(lookup "$r.1")" ps="$(lookup "$r-sha.1")"
  if [[ -z "$pd" || "$pd" == "$D" ]]; then
    pd="$(lookup "$r.0")" ps="$(lookup "$r-sha.0")"
  fi
  [[ -n "$pd" && "$pd" != "$D" ]] || return 0
  check "$r previous" "$pd" "$ps"
  echo "      { image_digest = \"$pd\", source_sha = \"$ps\" }, # previous" >> "$work/$r.images"
  echo "              + \"$pd\"," >> "$work/$r.gates"
  row "$r, previous" "$pd" "$ps" "$r" "kept from $PREV_TAG"
}
reader teecryptor "$IN_TEECRYPTOR_DIGEST" "$IN_TEECRYPTOR_SHA"
reader zee-k "$IN_ZEEK_DIGEST" "$IN_ZEEK_SHA"

{
  echo "          + teecryptor = ["
  cat "$work/teecryptor.gates"
  echo "            ]"
  echo "          + zee-k      = ["
  cat "$work/zee-k.gates"
  echo "            ]"
} > "$work/gates"
while read -r image digest _; do
  echo "$image-${digest#sha256:}.jsonl"
done < "$out/pairs" > "$work/bundles"

# A first apply with the default flags adds 14 fixed resources: 5 APIs, the
# audit config, 2 secrets, the write pool and provider, the reader pool, and 3
# reader providers (teecryptor, zee-k, keygen). Plus one read binding per
# reader digest, so the count follows the rendered list.
first_add=$((14 + $(grep -cv '^keygen ' "$out/pairs")))

render() {
  sed -e "s|__TAG__|$TAG|g" \
      -e "s|__FIRST_APPLY_ADD__|$first_add|g" \
      -e "s|__COMPUTE_PROJECT__|$COMPUTE_PROJECT|g" \
      -e "s|__KEYGEN_DIGEST__|$KEYGEN_DIGEST|g" \
      -e "s|__KEYGEN_SHA__|$KEYGEN_SHA|g" \
      -e "/__TEECRYPTOR_IMAGES__/r $work/teecryptor.images" -e "/__TEECRYPTOR_IMAGES__/d" \
      -e "/__ZEEK_IMAGES__/r $work/zee-k.images" -e "/__ZEEK_IMAGES__/d" \
      -e "/__PAIR_ROWS__/r $out/pairs.md" -e "/__PAIR_ROWS__/d" \
      -e "/__BUNDLE_LIST__/r $work/bundles" -e "/__BUNDLE_LIST__/d" \
      -e "/__READ_GATES__/r $work/gates" -e "/__READ_GATES__/d" \
      -e "/__PREVIOUS_DIFF__/r $work/diff.md" -e "/__PREVIOUS_DIFF__/d" \
      "$1"
}
render "$tmpl/values.tfvars.tmpl" > "$out/values.tfvars"
"$here/render-diff.sh" "$PREV_TAG" "$PREV_FILE" "$out/values.tfvars" "$TAG" > "$work/diff.md"
render "$tmpl/EXPECTED.md.tmpl" > "$out/EXPECTED.md"

# A placeholder left over means the template and this script drifted apart.
if grep -n '__[A-Z_]*__' "$out/values.tfvars" "$out/EXPECTED.md"; then
  die "a placeholder was not rendered"
fi
