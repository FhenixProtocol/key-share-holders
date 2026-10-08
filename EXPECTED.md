# Expected values for release v1.0.4

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
| keygen image digest (write gate) | `sha256:f2ea9c4802236eb0f3f3c42c8c5c6d8f02e062d136f8ac06ef7f34ac64688f69` |
| keygen source commit | `7f93823f135f47b794482b984870b42aef95468d` |
| teecryptor image digest (read gate on `cofhe-tee-fhe-priv`) | `sha256:bf5114a6fe877dbd18d734aeed53c3faee93192f9b7256c5d6e23e1659da63a2` |
| teecryptor source commit | `ffba731ab6162ef9eef471c1abbe6a124b998c06` |
| zee-k image digest (read gate on `cofhe-tee-zk-signer`) | `sha256:84591341cea631ec200df493b96f4e4797986f65e43f9d7ed2f5c9d10c5b5d09` |
| zee-k source commit | `cc3e1d633d6f1231032dd68c22a5f8295c810069` |

This tag also carries the signed proof for each digest above, in `partner/bundles`:

```
keygen-f2ea9c4802236eb0f3f3c42c8c5c6d8f02e062d136f8ac06ef7f34ac64688f69.jsonl
teecryptor-bf5114a6fe877dbd18d734aeed53c3faee93192f9b7256c5d6e23e1659da63a2.jsonl
zee-k-84591341cea631ec200df493b96f4e4797986f65e43f9d7ed2f5c9d10c5b5d09.jsonl
```

Your apply reads those three files. It calls no GitHub API. If one is absent, the check
downloads it from `api.github.com` instead, and the result is the same.

## What changes from v1.0.3

Changed: teecryptor, teecryptor-sha, zee-k, zee-k-sha

| Pin | v1.0.3 | v1.0.4 | |
|---|---|---|---|
| Fhenix compute project | `fhenix-mainnet` | `fhenix-mainnet` | unchanged |
| keygen (write gate) | `sha256:f2ea9c4802236eb0f3f3c42c8c5c6d8f02e062d136f8ac06ef7f34ac64688f69` | `sha256:f2ea9c4802236eb0f3f3c42c8c5c6d8f02e062d136f8ac06ef7f34ac64688f69` | unchanged |
| keygen source commit | `7f93823f135f47b794482b984870b42aef95468d` | `7f93823f135f47b794482b984870b42aef95468d` | unchanged |
| teecryptor (read gate on cofhe-tee-fhe-priv) | `sha256:c111fb96307039eea5ff0d3aa808f0146392c099c48bd417b8ac323bd566cbd9` | `sha256:bf5114a6fe877dbd18d734aeed53c3faee93192f9b7256c5d6e23e1659da63a2` | **CHANGED** |
| teecryptor source commit | `852f1160857ae5a81a41df546199156011fe6436` | `ffba731ab6162ef9eef471c1abbe6a124b998c06` | **CHANGED** |
| zee-k (read gate on cofhe-tee-zk-signer) | `sha256:75265b62e9bc90c7fc4c3ff0b03ba714aefece3796d55fe9c9af7bfaa95a5b2b` | `sha256:84591341cea631ec200df493b96f4e4797986f65e43f9d7ed2f5c9d10c5b5d09` | **CHANGED** |
| zee-k source commit | `ad2e30c3f10a4d1c9992d17a4e2d122ab56b272c` | `cc3e1d633d6f1231032dd68c22a5f8295c810069` | **CHANGED** |

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
      + write_gate_pins      = "sha256:f2ea9c4802236eb0f3f3c42c8c5c6d8f02e062d136f8ac06ef7f34ac64688f69"
      + read_gates_pin       = {
          + teecryptor = "sha256:bf5114a6fe877dbd18d734aeed53c3faee93192f9b7256c5d6e23e1659da63a2"
          + zee-k      = "sha256:84591341cea631ec200df493b96f4e4797986f65e43f9d7ed2f5c9d10c5b5d09"
        }
    }
```
