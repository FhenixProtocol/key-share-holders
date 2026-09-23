# Expected values for release v1.0.1

Rendered by `.github/workflows/release.yml` from the same inputs as `values.tfvars`.
Do not edit by hand. The next release overwrites this file.

Check every line below against your own `terraform plan` and your `verify/` output. If
one string differs, stop and send us the output. Do not repair anything by hand.

The **source commit** rows are the exception: they are proven by your plan rather than
printed by it, and they never reach a CEL. Read them back with
`terraform output provenance_verified`.

| What | Expected |
|---|---|
| Fhenix compute project | `fhenix-mainnet` |
| keygen image digest (write gate) | `sha256:78c1f33c60b1eb3a6d8ad657687c05708e44167b18bf599b08f4ab833a43519c` |
| keygen source commit | `01652062b703ca19b11a9959155de9ae21697e21` |
| teecryptor image digest (read gate on `cofhe-tee-fhe-priv`) | `sha256:591d0046c306c5ce37c4c604d11b181de707698f2f9432648b16638912c49cfb` |
| teecryptor source commit | `c5168e102742a31e89ff8f1ca3bd7f98a8c466c9` |
| zee-k image digest (read gate on `cofhe-tee-zk-signer`) | `sha256:291fcd710905cfc3b3ab1f0aa5a8fc062f6de9eb87a2f81674cfeab84bc5beec` |
| zee-k source commit | `f3382f20f23a64ae479bc8dfa8eb10990dd20424` |

This tag also carries the signed proof for each digest above, in `partner/bundles`:

```
keygen-78c1f33c60b1eb3a6d8ad657687c05708e44167b18bf599b08f4ab833a43519c.jsonl
teecryptor-591d0046c306c5ce37c4c604d11b181de707698f2f9432648b16638912c49cfb.jsonl
zee-k-291fcd710905cfc3b3ab1f0aa5a8fc062f6de9eb87a2f81674cfeab84bc5beec.jsonl
```

Your apply reads those three files. It calls no GitHub API. If one is absent, the check
downloads it from `api.github.com` instead, and the result is the same.

## What changes from v1.0.0

Changed: nothing. Only the documentation changed in this release.

If this is your first apply, ignore this section: the table above is what you check.

| Pin | v1.0.0 | v1.0.1 | |
|---|---|---|---|
| Fhenix compute project | `fhenix-mainnet` | `fhenix-mainnet` | unchanged |
| keygen (write gate) | `sha256:78c1f33c60b1eb3a6d8ad657687c05708e44167b18bf599b08f4ab833a43519c` | `sha256:78c1f33c60b1eb3a6d8ad657687c05708e44167b18bf599b08f4ab833a43519c` | unchanged |
| keygen source commit | `01652062b703ca19b11a9959155de9ae21697e21` | `01652062b703ca19b11a9959155de9ae21697e21` | unchanged |
| teecryptor (read gate on cofhe-tee-fhe-priv) | `sha256:591d0046c306c5ce37c4c604d11b181de707698f2f9432648b16638912c49cfb` | `sha256:591d0046c306c5ce37c4c604d11b181de707698f2f9432648b16638912c49cfb` | unchanged |
| teecryptor source commit | `c5168e102742a31e89ff8f1ca3bd7f98a8c466c9` | `c5168e102742a31e89ff8f1ca3bd7f98a8c466c9` | unchanged |
| zee-k (read gate on cofhe-tee-zk-signer) | `sha256:291fcd710905cfc3b3ab1f0aa5a8fc062f6de9eb87a2f81674cfeab84bc5beec` | `sha256:291fcd710905cfc3b3ab1f0aa5a8fc062f6de9eb87a2f81674cfeab84bc5beec` | unchanged |
| zee-k source commit | `f3382f20f23a64ae479bc8dfa8eb10990dd20424` | `f3382f20f23a64ae479bc8dfa8eb10990dd20424` | unchanged |

Your plan must show exactly the **CHANGED** rows above taking effect, and nothing
else. If a pin marked *unchanged* appears in your plan, or a resource is added or
destroyed that this table does not explain, stop and send us the plan.

## Your plan

If this is your **first** apply, expect **15 to add, 0 to change, 0 to destroy**. Two
more are added if you apply with `-var grant_write_access=true`, which we ask for only
around a key ceremony. Your plan also shows a `provenance_verified` output; that is the
proof the provenance check ran.

If you are **upgrading** from an earlier tag, the table above is the authority: your
plan must show those CHANGED rows taking effect and nothing else.

A changed **consumer** digest (teecryptor, zee-k) shows as 1 change plus 1 destroy and
1 add: its read binding names the digest inside the member string, which cannot be
edited, so the binding is replaced.

A changed **keygen** digest shows as 1 change. If you hold write access at the time, it
also destroys and adds the write binding, for the same reason: that binding names the
digest too.

Those destroys are expected. See *Apply a later release* in `PARTNER_GUIDE.md`.

## Your verify run

```
  + SUCCESS = {
      + partner_project      = "<your-project>"
      + write_gate_pins      = "sha256:78c1f33c60b1eb3a6d8ad657687c05708e44167b18bf599b08f4ab833a43519c"
      + read_gates_pin       = {
          + teecryptor = "sha256:591d0046c306c5ce37c4c604d11b181de707698f2f9432648b16638912c49cfb"
          + zee-k      = "sha256:291fcd710905cfc3b3ab1f0aa5a8fc062f6de9eb87a2f81674cfeab84bc5beec"
        }
    }
```
