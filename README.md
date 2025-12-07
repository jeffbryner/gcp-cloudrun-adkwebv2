# Why
Since GCP deprecated source repositories, there is a need for an updated deployment pattern that allows: 

- Easy adk with web ui deployment using:
  - Github hosted source
  - Cloudbuild triggers
  - Prod/Non-prod environment separation
  - Terraform/ci/cd


# CICD structure

A simple folder based structure

How it works:

Trigger A: Listens for changes in envs/dev/**. Points to envs/dev/cloudbuild.yaml.

Trigger B: Listens for changes in envs/prod/**. Points to envs/prod/cloudbuild.yaml.

Pros: Maximum clarity. You can't accidentally deploy dev config to prod.

Cons: "Drift." You might add a new feature to Dev but forget to copy the configuration block to Prod.
```
/
├── src/
├── cicd/
│   ├── dev/
│   │   ├── main.tf   (non-prod orientation for memory/settings/instances etc )
│   │   ├── backend.tf
│   │   └── cloudbuild.yaml
│   └── prod/
│       ├── main.tf   (prod orientation for memory/settings/instances, etc)
│       ├── backend.tf
│       └── cloudbuild.yaml

```
