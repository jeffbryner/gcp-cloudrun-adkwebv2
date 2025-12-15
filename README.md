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


## Usage / Bootstrapping
To get started we will take the repo and bootstrap ourselves into a GCP cloudbuild pipeline. 

- clone the repo, operate in the ```main``` branch 
- set the varables in the .tfvars files (use .tfvars.example as a guide)
- open a shell in cicd/dev
- render the backend.tf file inert (we don't have a bucket yet) by renaming to backend.tf.inert
- run ```terraform init``` to initialize terraform and providers. 
- run ```terraform plan``` to check the build plan
- run ```terraform apply -target=module.gcp_project_setup``` to bootstrap the project and build pipeline



Note that terraform may not complete due to some chicken/egg problems. 
- Some services may not complete activiation: Solution: wait a bit to allow activation and retry
- Authorization: If you do not have the google cloudbuild app for github installed, you'll need to follow steps below

## Authorization
You will need to authorize the google cloudbuild app to access your github repo. 
Terraform will fail, and offer a URL like: 
https://console.cloud.google.com/cloud-build/triggers;region=global/connect?project=123456789

Clicking it will take you to GCP to complete the authorization. You do not need to create triggers.

![Google App Authorization](static/google_app_authorization.png) 


Before turning things over to the CICD pipeline, you will need to set the state bucket: 

Rename backend.tf.inert to backend.tf to enable state to be stored in the bucket created in the bootstrap step. 

Then re-init terraform to allow it to transfer state to GCS: 
From /cicd/dev and /cicd/prod (once you have dev working)
```
terraform init -force-copy -backend-config="bucket=<name of the bucket from terraform -output>"
```

Lastly, to avoid terraform vars ending up in a repo AND to allow our CICD pipeline to use the terraform state in the bucket we will add variables to the 'tfvars' google cloud secret. 

Create a text file with  the following variables:
(don't include the <> brackets, but do enclose in quotes) 

org_id          = "<your gcp org id number>"
billing_account = "<your billing account GUID>"
project_name    = "<your friendly name for the project>"
folder_id       = "<the integer number of the folder where youd like the project to live>"
github_org      = "<your githug org name>"
github_repo     = "<the github repo you want to use>"
bucket          = "<name of the bucket from terraform -output>"

In the GCP console for secret manager https://console.cloud.google.com/security/secret-manager
Upload this file as a new 'version' of the 'tfvars' secret. This will be used by cloudbuild at build time. 
Note: Technically the bucket isn't a real terraform variable, but we store it here harmlessly as a way to avoid having to store extra secrets just for another variable. 

Create a ```dev``` branch and push a change to trigger the CICD pipeline to run. 