#!/usr/bin/env bash
# Render the "what changes from the previous release" section of EXPECTED.md.
#
# Pure git and text: it compares the previous tag's values.tfvars with the one just
# rendered. It needs no credentials, so it runs in a repo that can reach no project.
#
#   render-diff.sh <prev_tag|""> <prev_values_file|""> <new_values_file> <new_tag>
set -euo pipefail

prev_tag="${1:-}"
prev_file="${2:-}"
new_file="$3"
new_tag="$4"
here="$(cd "$(dirname "$0")" && pwd)"

if [[ -z "$prev_tag" || ! -s "$prev_file" ]]; then
  printf '%s\n' \
    "## What changes from the previous release" \
    "" \
    "This is the first release to carry a rendered \`values.tfvars\`. There is no" \
    "earlier tag to compare against, so every pin in the table above is new to you."
  exit 0
fi

# Own directory, not fixed /tmp names: two releases on one runner would
# overwrite each other, and a pre-placed symlink at a fixed name is followed.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
awk -f "$here/pins.awk" "$prev_file" > "$work/pins.prev"
awk -f "$here/pins.awk" "$new_file"  > "$work/pins.new"

lookup() { awk -v k="$1" '$1 == k { print $2 }' "$2"; }

changed=""
rows=""
for key in compute keygen keygen-sha; do
  old="$(lookup "$key" "$work/pins.prev")"
  new="$(lookup "$key" "$work/pins.new")"
  case "$key" in
    compute)    label="Fhenix compute project" ;;
    keygen)     label="keygen (write gate)" ;;
    keygen-sha) label="keygen source commit" ;;
  esac
  if [[ "$old" == "$new" ]]; then
    rows="$rows| $label | \`$old\` | \`$new\` | unchanged |"$'\n'
  else
    changed="$changed $key"
    rows="$rows| $label | \`${old:-(absent)}\` | \`$new\` | **CHANGED** |"$'\n'
  fi
done

# A reader lists 1 or 2 images, and a digest can move from index 0 to index 1,
# so match the images by digest, not by index. One row per digest.
pairs() {  # reader, pins file: "<digest> <sha> <index>" per image
  awk -v r="$1" '$1 ~ "^" r "\\.[0-9]+$" { i = substr($1, length(r) + 2); d[i] = $2 }
                 $1 ~ "^" r "-sha\\.[0-9]+$" { i = substr($1, length(r) + 6); s[i] = $2 }
                 END { for (i = 0; i in d; i++) print d[i], s[i], i }' "$2"
}
for r in teecryptor zee-k; do
  case "$r" in
    teecryptor) gate="(read gate on cofhe-tee-fhe-priv)" ;;
    zee-k)      gate="(read gate on cofhe-tee-zk-signer)" ;;
  esac
  pairs "$r" "$work/pins.prev" > "$work/$r.prev"
  pairs "$r" "$work/pins.new"  > "$work/$r.new"
  moved=""
  label() { if [[ "$1" == 0 ]]; then echo "$r $gate"; else echo "$r, previous $gate"; fi; }
  while read -r d s i; do
    label="$(label "$i")"
    old="$(awk -v d="$d" '$1 == d { print $2 }' "$work/$r.prev")"
    if [[ -z "$old" ]]; then
      moved=1
      rows="$rows| $label | (absent) | \`$d\` from \`$s\` | **ADDED** |"$'\n'
    elif [[ "$old" != "$s" ]]; then
      moved=1
      rows="$rows| $label | \`$d\` from \`$old\` | \`$d\` from \`$s\` | **CHANGED** |"$'\n'
    else
      rows="$rows| $label | \`$d\` from \`$s\` | \`$d\` from \`$s\` | unchanged |"$'\n'
    fi
  done < "$work/$r.new"
  while read -r d s i; do
    if ! awk -v d="$d" '$1 == d { f = 1 } END { exit !f }' "$work/$r.new"; then
      moved=1
      rows="$rows| $(label "$i") | \`$d\` from \`$s\` | (absent) | **REMOVED** |"$'\n'
    fi
  done < "$work/$r.prev"
  [[ -z "$moved" ]] || changed="$changed $r"
done

# FIRST-LIST-RELEASE: first_list, its "Changed" line, its block and $explained.
first_list=""
[[ "$(lookup shape "$work/pins.prev")" != flat ]] || first_list=1

printf '%s\n' "## What changes from $prev_tag" ""
if [[ -n "$first_list" && -z "$changed" ]]; then
  printf '%s\n' \
    "Changed: no pin. The read bindings move to image lists: see *First release with" \
    "image lists* below." \
    ""
elif [[ -z "$changed" ]]; then
  # A docs-only release. Nobody had applied the previous tag when this shipped, so
  # say who the section is for; "Changed: nothing" alone reads as a missed step.
  printf '%s\n' \
    "Changed: nothing. Only the documentation changed in this release." \
    "" \
    "If this is your first apply, ignore this section: the table above is what you check." \
    ""
else
  printf 'Changed: %s\n\n' "$(echo "$changed" | sed 's/^ //; s/ /, /g')"
fi
printf '%s\n' "| Pin | $prev_tag | $new_tag | |" "|---|---|---|---|"
printf '%s' "$rows"

# FIRST-LIST-RELEASE
# The previous release pinned one digest per reader: this apply also moves the
# read bindings to the per-image resource. Those lines are expected, not drift.
if [[ -n "$first_list" ]]; then
  printf '%s\n' \
    "" \
    "### First release with image lists" \
    "" \
    "$prev_tag pins one digest per reader. This release lists images. On top of the rows" \
    "above, expect **3 to add, 2 to change, 0 to destroy**, and each \`attested_read\`" \
    "binding \"will no longer be managed by Terraform\". Apply it with read access on: do" \
    "not pass \`grant_read_access=false\`. What each line means, and how a moved image or" \
    "an existing \`keygen-reader\` changes the counts: see *The first release with image" \
    "lists* in \`PARTNER_GUIDE.md\`."
  explained="the table and the block above do"
else
  explained="this table does"
fi
printf '%s\n' \
  "" \
  "Your plan must show exactly the **CHANGED**, **ADDED** and **REMOVED** rows above" \
  "taking effect, and nothing else. If a pin marked *unchanged* appears in your plan," \
  "or a resource is added, destroyed or no longer managed and $explained not" \
  "explain it, stop and send us the plan."
