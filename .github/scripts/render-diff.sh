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
unchanged=""
rows=""
for key in compute keygen keygen-sha teecryptor teecryptor-sha zee-k zee-k-sha; do
  old="$(lookup "$key" "$work/pins.prev")"
  new="$(lookup "$key" "$work/pins.new")"
  case "$key" in
    compute)        label="Fhenix compute project" ;;
    keygen)         label="keygen (write gate)" ;;
    keygen-sha)     label="keygen source commit" ;;
    teecryptor)     label="teecryptor (read gate on cofhe-tee-fhe-priv)" ;;
    teecryptor-sha) label="teecryptor source commit" ;;
    zee-k)          label="zee-k (read gate on cofhe-tee-zk-signer)" ;;
    zee-k-sha)      label="zee-k source commit" ;;
    *)              label="$key" ;;
  esac
  if [[ "$old" == "$new" ]]; then
    unchanged="$unchanged $key"
    rows="$rows| $label | \`$old\` | \`$new\` | unchanged |"$'\n'
  else
    changed="$changed $key"
    rows="$rows| $label | \`${old:-(absent)}\` | \`$new\` | **CHANGED** |"$'\n'
  fi
done

printf '%s\n' "## What changes from $prev_tag" ""
if [[ -z "$changed" ]]; then
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
printf '%s\n' \
  "" \
  "Your plan must show exactly the **CHANGED** rows above taking effect, and nothing" \
  "else. If a pin marked *unchanged* appears in your plan, or a resource is added or" \
  "destroyed that this table does not explain, stop and send us the plan."
