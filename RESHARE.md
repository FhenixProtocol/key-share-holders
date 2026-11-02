# A reshare (only when Fhenix asks)

This page is for key-share holders. It follows [PARTNER_GUIDE.md](PARTNER_GUIDE.md): run
the commands from `partner/` in your clone, with `PROJECT` set as in that guide.

A reshare moves the key shares to a new partner set, for example when a key-share
holder joins or leaves. **The key does not change.** The keygen image reads the current
shares at one version number, splits the same key again, and writes the new shares at
a higher version number. Every partner holds the new shares at the same number. Fhenix
tells you which tags to apply and which flags to set.

The steps:

1. **You apply tag A with the flags for your role** (table below). Tag A also carries
   the new consumer images next to the old ones.
2. **Fhenix runs the keygen.** It writes the new version and its public manifest.
3. **Fhenix deploys the new consumers.** The old consumers keep reading the old version
   until they are replaced.
4. **After Fhenix confirms the run and the new consumers, you apply tag B without the
   flags.** That disables the gate and removes the old consumer images, the keygen read,
   the version list and the write.

| Your role in the reshare | Flags for the tag A apply |
|---|---|
| You hold a share now, and you stay | `-var grant_reshare_read=true -var grant_write_access=true` |
| You hold a share now, and you leave | `-var grant_reshare_read=true` (optional: the run needs only the old threshold of shares) |
| You join | `-var grant_write_access=true` (normal onboarding) |

Plan first. The provider `keygen-reader` already exists, disabled. With
`grant_reshare_read=true`, expect it to be enabled (1 change) and two `secretAccessor` bindings,
one on each secret, for the keygen image digest. With `grant_write_access=true`, expect
the four write-window bindings from [step 8](PARTNER_GUIDE.md#8-grant-write-access). The rows of
`EXPECTED.md` add to this:

```bash
terraform plan -var-file=../values.tfvars -var partner_project_id=$PROJECT \
  -var grant_reshare_read=true   # add -var grant_write_access=true if you stay
#   ~ google_iam_workload_identity_pool_provider.reader["keygen"]   disabled = true -> false
#   + google_secret_manager_secret_iam_member.reshare_read["cofhe-tee-fhe-priv"]
#   + google_secret_manager_secret_iam_member.reshare_read["cofhe-tee-zk-signer"]
#   + google_secret_manager_secret_iam_member.attested_add[...]            (only if you stay)
#   + google_secret_manager_secret_iam_member.keygen_version_viewer[...]   (only if you stay)
```

Apply, then run `verify/` with the same flags. It checks the reshare gate and expects
the keygen image as a reader.

**What you may see during the run.** The keygen first lists your versions. If your
newest version number is below the target minus one, it adds small filler versions
until the next number is the target. A filler holds the bytes `de ad be ef`, not key
material. Then it writes your share at the target number. The fillers cost nothing.

After tag B, run `verify/` again: the SUCCESS block shows `reshare_read_granted = false`
and `write_access_granted = false`.

> **Keep your old secret versions.** A reshare adds a new version and leaves the old
> ones. Do not destroy them or a filler. If you leave the partner set, do not delete
> your secret. A rollback reads the old versions. Fhenix asks you explicitly if one
> must go.

**If the run stops, you do nothing.** Your old version and the old manifest do not
change, so the running consumers are not affected. A stop before the first share
reruns the same image. A stop after a share needs a new keygen image with a higher
version number, so we send you a new tag A. That tag keeps the consumer image that
still runs, and replaces a new image that never ran. A version that the stopped run
wrote stays as an older version that no reader uses.

Fhenix rolls every pod back to the older image of the overlap before it sends a
fix-forward tag A. Apply that tag when we ask.
