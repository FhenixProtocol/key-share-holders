# Print "<name> <value>" for each pin in a rendered values.tfvars.
# The file is generated from our own template, so the shape is fixed: the
# top-level image_digest is the keygen write gate, and each attested_readers
# block names its consumer before its images.
#
# A reader pin prints as "<reader>.<i> <digest>" and "<reader>-sha.<i> <sha>".
# FIRST-LIST-RELEASE: the flat shape, the two flat blocks and the shape line.
# Two reader shapes are read, because the first list release must carry the
# digests of the last flat one:
#   flat: image_digest = / source_sha = lines inside the reader block, index 0
#   list: one "{ image_digest = ..., source_sha = ... }," line per image
# The last line is "shape flat" or "shape list".
/^service_project_id/ {
  if (match($0, /"[^"]+"/)) print "compute " substr($0, RSTART + 1, RLENGTH - 2)
}
/^image_digest/ {
  if (match($0, /sha256:[0-9a-f]{64}/)) print "keygen " substr($0, RSTART, RLENGTH)
}
/^source_sha/ {
  if (match($0, /[0-9a-f]{40}/)) print "keygen-sha " substr($0, RSTART, RLENGTH)
}
/^[[:space:]]+[A-Za-z0-9_-]+[[:space:]]*=[[:space:]]*\{/ {
  consumer = $1
  n = 0
}
# FIRST-LIST-RELEASE: flat reader digest.
/^[[:space:]]+image_digest/ {
  if (consumer != "" && match($0, /sha256:[0-9a-f]{64}/)) {
    print consumer ".0 " substr($0, RSTART, RLENGTH)
    shape = "flat"
  }
}
# FIRST-LIST-RELEASE: flat reader commit.
/^[[:space:]]+source_sha/ {
  if (consumer != "" && match($0, /[0-9a-f]{40}/)) {
    print consumer "-sha.0 " substr($0, RSTART, RLENGTH)
  }
}
# The sha is matched with its key: a bare 40-hex match would hit the digest.
/^[[:space:]]+\{.*image_digest/ {
  if (consumer != "" && match($0, /sha256:[0-9a-f]{64}/)) {
    print consumer "." n " " substr($0, RSTART, RLENGTH)
    if (match($0, /source_sha[[:space:]]*=[[:space:]]*"[0-9a-f]{40}"/)) {
      s = substr($0, RSTART, RLENGTH)
      print consumer "-sha." n " " substr(s, length(s) - 40, 40)
    }
    n++
    shape = "list"
  }
}
# Clear at the end of the BLOCK, never on one of its fields. Clearing on a field
# makes the output depend on field order, and a reordered block would then print
# nothing for the missed pin, which render-diff.sh reports as "unchanged".
/^[[:space:]]+\}/ {
  consumer = ""
}
# FIRST-LIST-RELEASE: the shape line and both "shape =" assignments.
END {
  if (shape != "") print "shape " shape
}
