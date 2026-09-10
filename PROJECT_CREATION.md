# Project Creation

You create a Google Cloud project and send us two values: its project id and its project number.

## 1. Creation
Please create the following:
 
A **dedicated GCP project** with billing enabled. Secret Manager and IAM only. No compute, no servers.
- `roles/owner` or `roles/resourcemanager.projectIamAdmin` on this project.
- `gcloud`

```bash
gcloud auth login
gcloud auth application-default login
gcloud projects describe <your-project> --format='value(projectId,projectNumber)'
```
