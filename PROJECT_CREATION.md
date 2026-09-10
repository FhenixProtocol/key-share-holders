# Project Creation

You create a Google Cloud project. 

**You supply exactly two values: your own project id and the project number**

## 1. Creation
Please create the following:

- A **dedicated GCP project** with billing enabled. Secret Manager and IAM only. No
  compute, no servers.
- `roles/owner` or `roles/resourcemanager.projectIamAdmin` on this project.
- `gcloud`

```bash
gcloud auth login
gcloud auth application-default login
```
