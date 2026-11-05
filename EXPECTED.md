# Expected values for release v1.0.7

Rendered by `.github/workflows/release.yml` from the same inputs as `values.tfvars`.
Do not edit by hand. The next release overwrites this file.

Check every line below against your own `terraform plan` and your `verify/` output. If
one string differs, stop and send us the output. Do not repair anything by hand.

The **source commit** column is the exception: it is proven by your plan rather than
printed by it, and it never reaches a CEL. Read it back with
`terraform output provenance_verified`.

Fhenix compute project: `fhenix-mainnet`.

keygen is the write gate. teecryptor reads `cofhe-tee-fhe-priv` and zee-k reads
`cofhe-tee-zk-signer`. A reader row marked *previous* is the previous release's image,
kept while an upgrade is in progress.

| Image | Digest | Source commit |
|---|---|---|
| keygen (write gate) | `sha256:781096676f8f7ad690e50b6cc58974b00f581d7f168e46bfb0d7a65a087fcc35` | `4a816b9090ded5ef8f6be75cb067fc7c20c7a9dc` |
| teecryptor | `sha256:69e26a0c6300e32878e1ab735592d357c7bcfdc978cff3206a5d3840d945179a` | `7099fc89bb8ac423aca281c23a32b1ac5acca371` |
| teecryptor, previous | `sha256:ae85f4d29ea0def0a6748bf75cf319e2236d9800c9fb5b22de5d09319dc79624` | `6dd84e784d359cbe81db9cc0a4ecb5b5d28e722d` |
| zee-k | `sha256:7f757e6abcd4ff49e0c67e825505d2cd9f019f1a6a8649fc7a0257c5b9113fe1` | `91d81d3df5618a01106c2f345a6fa1eab91cc0de` |
| zee-k, previous | `sha256:e773b9cc9f72dc87906d05c6f8e96ac8e8dd7480db3d6e66f3b3b20d58ea8ad4` | `47a59438caa7390582d4c470df7a02c42fa21d85` |

This tag also carries the signed proof for each digest above, in `partner/bundles`:

```
keygen-781096676f8f7ad690e50b6cc58974b00f581d7f168e46bfb0d7a65a087fcc35.jsonl
teecryptor-69e26a0c6300e32878e1ab735592d357c7bcfdc978cff3206a5d3840d945179a.jsonl
teecryptor-ae85f4d29ea0def0a6748bf75cf319e2236d9800c9fb5b22de5d09319dc79624.jsonl
zee-k-7f757e6abcd4ff49e0c67e825505d2cd9f019f1a6a8649fc7a0257c5b9113fe1.jsonl
zee-k-e773b9cc9f72dc87906d05c6f8e96ac8e8dd7480db3d6e66f3b3b20d58ea8ad4.jsonl
```

Your apply reads those files. It calls no GitHub API. If one is absent, the check
downloads it from `api.github.com` instead, and the result is the same.

## What changes from v1.0.6

Changed: keygen, keygen-sha, teecryptor, zee-k

| Pin | v1.0.6 | v1.0.7 | |
|---|---|---|---|
| Fhenix compute project | `fhenix-mainnet` | `fhenix-mainnet` | unchanged |
| keygen (write gate) | `sha256:f2ea9c4802236eb0f3f3c42c8c5c6d8f02e062d136f8ac06ef7f34ac64688f69` | `sha256:781096676f8f7ad690e50b6cc58974b00f581d7f168e46bfb0d7a65a087fcc35` | **CHANGED** |
| keygen source commit | `7f93823f135f47b794482b984870b42aef95468d` | `4a816b9090ded5ef8f6be75cb067fc7c20c7a9dc` | **CHANGED** |
| teecryptor (read gate on cofhe-tee-fhe-priv) | (absent) | `sha256:69e26a0c6300e32878e1ab735592d357c7bcfdc978cff3206a5d3840d945179a` from `7099fc89bb8ac423aca281c23a32b1ac5acca371` | **ADDED** |
| teecryptor, previous (read gate on cofhe-tee-fhe-priv) | `sha256:ae85f4d29ea0def0a6748bf75cf319e2236d9800c9fb5b22de5d09319dc79624` from `6dd84e784d359cbe81db9cc0a4ecb5b5d28e722d` | `sha256:ae85f4d29ea0def0a6748bf75cf319e2236d9800c9fb5b22de5d09319dc79624` from `6dd84e784d359cbe81db9cc0a4ecb5b5d28e722d` | unchanged |
| zee-k (read gate on cofhe-tee-zk-signer) | (absent) | `sha256:7f757e6abcd4ff49e0c67e825505d2cd9f019f1a6a8649fc7a0257c5b9113fe1` from `91d81d3df5618a01106c2f345a6fa1eab91cc0de` | **ADDED** |
| zee-k, previous (read gate on cofhe-tee-zk-signer) | `sha256:e773b9cc9f72dc87906d05c6f8e96ac8e8dd7480db3d6e66f3b3b20d58ea8ad4` from `47a59438caa7390582d4c470df7a02c42fa21d85` | `sha256:e773b9cc9f72dc87906d05c6f8e96ac8e8dd7480db3d6e66f3b3b20d58ea8ad4` from `47a59438caa7390582d4c470df7a02c42fa21d85` | unchanged |

### First release with image lists

v1.0.6 pins one digest per reader. This release lists images. On top of the rows
above, expect **3 to add, 2 to change, 0 to destroy**, and each `attested_read`
binding "will no longer be managed by Terraform". Apply it with read access on: do
not pass `grant_read_access=false`. What each line means, and how a moved image or
an existing `keygen-reader` changes the counts: see *The first release with image
lists* in `PARTNER_GUIDE.md`.

Your plan must show exactly the **CHANGED**, **ADDED** and **REMOVED** rows above
taking effect, and nothing else. If a pin marked *unchanged* appears in your plan,
or a resource is added, destroyed or no longer managed and the table and the block above do not
explain it, stop and send us the plan.

## Your plan

If this is your **first** apply, expect **18 to add, 0 to change, 0 to destroy**:
14 fixed resources, plus one read binding per reader digest in the table above. Four
more are added if you apply with `-var grant_write_access=true`, which we ask for only
around a key ceremony: on each secret, the write binding and the version-list binding.
Two more are added with `-var grant_reshare_read=true`, only around a reshare. Your
plan also shows a `provenance_verified` output; that is the proof the provenance check
ran.

If you are **upgrading** from an earlier tag, the table above is the authority: your
plan must show those CHANGED, ADDED and REMOVED rows taking effect and nothing else.
<!-- FIRST-LIST-RELEASE -->
A *First release with image lists* block above, if present, adds its own lines.

What each row does to the plan, and which bindings a new keygen digest replaces, is in
*Apply a later release* in `PARTNER_GUIDE.md`. The destroys there are expected.

## Your verify run

The two `_granted` lines print `true` only while you apply with those flags.

```
  + SUCCESS = {
      + partner_project      = "<your-project>"
      + read_gates_pin       = {
          + teecryptor = [
              + "sha256:69e26a0c6300e32878e1ab735592d357c7bcfdc978cff3206a5d3840d945179a",
              + "sha256:ae85f4d29ea0def0a6748bf75cf319e2236d9800c9fb5b22de5d09319dc79624",
            ]
          + zee-k      = [
              + "sha256:7f757e6abcd4ff49e0c67e825505d2cd9f019f1a6a8649fc7a0257c5b9113fe1",
              + "sha256:e773b9cc9f72dc87906d05c6f8e96ac8e8dd7480db3d6e66f3b3b20d58ea8ad4",
            ]
        }
      + reshare_read_granted = false
      + write_access_granted = false
      + write_gate_pins      = "sha256:781096676f8f7ad690e50b6cc58974b00f581d7f168e46bfb0d7a65a087fcc35"
    }
```
