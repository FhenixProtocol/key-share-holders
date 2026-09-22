# Print "<name> <value>" for each pin in a rendered values.tfvars.
# The file is generated from our own template, so the shape is fixed: the
# top-level image_digest is the keygen write gate, and each attested_readers
# block names its consumer before its own image_digest.
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
}
/^[[:space:]]+image_digest/ {
  if (consumer != "" && match($0, /sha256:[0-9a-f]{64}/)) {
    print consumer " " substr($0, RSTART, RLENGTH)
  }
}
/^[[:space:]]+source_sha/ {
  if (consumer != "" && match($0, /[0-9a-f]{40}/)) {
    print consumer "-sha " substr($0, RSTART, RLENGTH)
  }
}
# Clear at the end of the BLOCK, never on one of its fields. Clearing on a field
# makes the output depend on field order, and a reordered block would then print
# nothing for the missed pin — which render-diff.sh reports as "unchanged".
/^[[:space:]]+\}/ {
  consumer = ""
}
