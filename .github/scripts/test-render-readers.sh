#!/usr/bin/env bash
# Render a release from each fixture and check the readers terraform sees.
# CI runs it; it needs terraform and the partner module's providers, no network
# to Sigstore: the proof step of release.yml is not part of the render.
#
#   test-render-readers.sh            (TERRAFORM overrides the binary)
set -euo pipefail

tf="${TERRAFORM:-terraform}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
fx="$root/.github/release-fixtures"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# A copy, so init and the override never touch the checkout.
cp -r "$root/partner" "$work/partner"
# console needs an initialised backend; the gcs one needs credentials CI lacks.
printf 'terraform {\n  backend "local" {}\n}\n' > "$work/partner/zz_console_override.tf"
"$tf" -chdir="$work/partner" init -input=false > /dev/null

new_tc="sha256:$(printf 'a%.0s' {1..64})"
new_tc_sha="$(printf 'b%.0s' {1..40})"
flat_tc="sha256:bf5114a6fe877dbd18d734aeed53c3faee93192f9b7256c5d6e23e1659da63a2@ffba731ab6162ef9eef471c1abbe6a124b998c06"
flat_zk="sha256:84591341cea631ec200df493b96f4e4797986f65e43f9d7ed2f5c9d10c5b5d09@cc3e1d633d6f1231032dd68c22a5f8295c810069"
keygen_pin="sha256:f2ea9c4802236eb0f3f3c42c8c5c6d8f02e062d136f8ac06ef7f34ac64688f69@7f93823f135f47b794482b984870b42aef95468d"
list_tc="sha256:1111111111111111111111111111111111111111111111111111111111111111@2222222222222222222222222222222222222222"
list_zk="sha256:3333333333333333333333333333333333333333333333333333333333333333@4444444444444444444444444444444444444444"

render() {  # <prev fixture> <keep> <teecryptor digest> <teecryptor sha> <out dir>
  mkdir -p "$5"
  TAG=v9.9.9 COMPUTE_PROJECT=fhenix-mainnet PREV_TAG=v9.9.8 PREV_FILE="$fx/$1" \
    KEEP_PREVIOUS_READERS="$2" \
    IN_KEYGEN_DIGEST="" IN_KEYGEN_SHA="" \
    IN_TEECRYPTOR_DIGEST="$3" IN_TEECRYPTOR_SHA="$4" \
    IN_ZEEK_DIGEST="" IN_ZEEK_SHA="" \
    "$root/.github/scripts/render-readers.sh" "$5" > "$5.log" 2>&1
}

# case <name> <prev fixture> <keep> <teecryptor digest> <teecryptor sha> <want teecryptor> <want zee-k>
# A want is the "<digest>@<sha>" list, comma-separated, in rendered order.
run_case() {
  local name="$1" out="$work/$1"
  echo "== $name"
  render "$2" "$3" "$4" "$5" "$out" \
    || { cat "$out.log"; echo "FAIL $name: render failed"; return 1; }
  "$tf" fmt -check -diff "$out/values.tfvars"
  local got
  # One expression: a piped console printed only its last result.
  got="$(echo 'join(" ", [for r in ["teecryptor", "zee-k"] : join(",", [for i in var.attested_readers[r].images : "${i.image_digest}@${i.source_sha}"])])' \
    | "$tf" -chdir="$work/partner" console -var-file="$out/values.tfvars" -var partner_project_id=render-check)"
  local want="\"$6 $7\""
  if [[ "$got" != "$want" ]]; then
    printf 'FAIL %s\n got:\n%s\n want:\n%s\n' "$name" "$got" "$want"
    return 1
  fi
  # The proof step proves exactly the pairs file: it must hold every rendered
  # pair, and nothing else.
  want="$({
    echo "keygen@$keygen_pin"
    printf '%s\n' "$6" | tr ',' '\n' | sed 's/^/teecryptor@/'
    printf '%s\n' "$7" | tr ',' '\n' | sed 's/^/zee-k@/'
  } | tr '@' ' ')"
  got="$(cat "$out/pairs")"
  if [[ "$got" != "$want" ]]; then
    printf 'FAIL %s: pairs\n got:\n%s\n want:\n%s\n' "$name" "$got" "$want"
    return 1
  fi
  local n
  n=$((14 + $(printf '%s,%s' "$6" "$7" | tr ',' '\n' | grep -c .)))
  grep -qF "expect **$n to add" "$out/EXPECTED.md" \
    || { echo "FAIL $name: EXPECTED.md does not expect $n to add"; return 1; }
  # FIRST-LIST-RELEASE
  # Only a flat previous release gets the first-list block, and it never reads
  # as "nothing changed".
  if [[ "$2" == prev-flat.tfvars ]]; then
    grep -qF "### First release with image lists" "$out/EXPECTED.md" \
      || { echo "FAIL $name: no first-list block"; return 1; }
    ! grep -qF "Changed: nothing" "$out/EXPECTED.md" \
      || { echo "FAIL $name: first list release says nothing changed"; return 1; }
  elif grep -qF "### First release with image lists" "$out/EXPECTED.md"; then
    echo "FAIL $name: first-list block after a list release"; return 1
  fi
  echo "PASS $name"
}

# prev-list.tfvars: teecryptor lists 2 images (list_tc, flat_tc), zee-k 1.
# FIRST-LIST-RELEASE
run_case flat-keep prev-flat.tfvars true "$new_tc" "$new_tc_sha" \
  "$new_tc@$new_tc_sha,$flat_tc" "$flat_zk"
run_case list-drop prev-list.tfvars false "" "" "$list_tc" "$list_zk"
run_case list-keep-unchanged prev-list.tfvars true "" "" "$list_tc,$flat_tc" "$list_zk"
# An open overlap [A, B] with a new C keeps B, the image that still runs: [C, B].
run_case list-keep-new prev-list.tfvars true "$new_tc" "$new_tc_sha" \
  "$new_tc@$new_tc_sha,$flat_tc" "$list_zk"
grep -F "| \`${list_tc%@*}\` from \`${list_tc#*@}\` | (absent) | **REMOVED** |" "$work/list-keep-new/EXPECTED.md" > /dev/null \
  || { echo "FAIL list-keep-new: A is not REMOVED in EXPECTED.md"; exit 1; }
# Re-supplying the older image B never lists it twice: [B, A].
run_case list-keep-older prev-list.tfvars true "${flat_tc%@*}" "${flat_tc#*@}" \
  "$flat_tc,$list_tc" "$list_zk"

# FIRST-LIST-RELEASE: the flat-drop case, to its PASS line.
echo "== flat-drop"
msg="the previous release uses one digest per reader; keep it once (keep_previous_readers=true)"
if render prev-flat.tfvars false "" "" "$work/flat-drop"; then
  echo "FAIL flat-drop: keep=false over a flat release rendered"; exit 1
fi
grep -qF "$msg" "$work/flat-drop.log" || { cat "$work/flat-drop.log"; echo "FAIL flat-drop: wrong message"; exit 1; }
echo "PASS flat-drop"
