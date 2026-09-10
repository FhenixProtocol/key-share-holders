# Project Creation

You create a Google Cloud project. You put the configuration file that we send you
into it. You apply. This creates two Secret Manager entries and the IAM rules that
decide **which attested Fhenix enclave can write your key share, and which can read
it**.

**Time: 1 to 2 hours, one time.** After this, nothing runs on your side. We are on the
call with you.

> **We send you one thing: a release tag in this repository.**
> The tag carries everything — the Terraform, this guide, the `values.tfvars` with
> every shared value already filled in, and the `EXPECTED.md` that lists the exact
> strings your checks must show. Every partner gets the same tag.
>
> **You supply exactly one value: your own project id**, and you pass it on the
> command line. You never type a Fhenix project id or an image digest into a file. If
> a step seems to ask you to, stop and ask us. A typed value is the most probable
> cause of an error.

> **You run each apply in your project. We cannot.** Fhenix has read-only access to
> your project. We check and we advise; you execute. This is by design. The Terraform
> that sets the IAM on your secrets needs one permission
> (`secretmanager.secrets.setIamPolicy`). The holder of that permission can give
> read access on a share to itself. We do not take it. See step 3.

## 0. Prerequisites

- A **dedicated GCP project** with billing enabled. Secret Manager and IAM only. No
  compute, no servers.
- `roles/owner` or `roles/resourcemanager.projectIamAdmin` on this project.
- `terraform` 1.9 or later, and `gcloud`.

```bash
gcloud auth login
gcloud auth application-default login   # Terraform uses this
```
