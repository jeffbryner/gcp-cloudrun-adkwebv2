terraform {
  required_providers {
    google      = "~> 4.0"
    google-beta = "~> 4.0"
  }

}

resource "random_id" "suffix" {
  byte_length = 2
}

locals {
  project_name      = "prj-dev-${var.project_name}"
  project_id        = "prj-dev-${var.project_name}-${random_id.suffix.hex}"
  project_org_id    = var.folder_id != "" ? null : var.org_id
  project_folder_id = var.folder_id != "" ? var.folder_id : null
  state_bucket_name = format("bkt-%s-%s", "tfstate", local.project_id)
  art_bucket_name   = format("bkt-%s-%s", "artifacts", local.project_id)
  services = [
    "cloudbilling.googleapis.com",
    "cloudbuild.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
  ]
}


resource "google_project" "target_project" {
  name                = local.project_name
  project_id          = local.project_id
  org_id              = local.project_org_id
  folder_id           = local.project_folder_id
  billing_account     = var.billing_account
  auto_create_network = false
  labels              = var.project_labels
}

# bucket for terraform state
resource "google_storage_bucket" "project_terraform_state" {
  project                     = google_project.target_project.project_id
  name                        = local.state_bucket_name
  location                    = var.default_region
  uniform_bucket_level_access = true
  force_destroy               = true
  versioning {
    enabled = true
  }
}

# enable required services in the project
resource "google_project_service" "services" {
  for_each           = toset(local.services)
  project            = google_project.target_project.project_id
  service            = each.value
  disable_on_destroy = false
}


# Custom Service Account for Cloud Build to deploy infrastructure
resource "google_service_account" "cloudbuild_sa" {
  project      = google_project.target_project.project_id
  account_id   = "terraform-deployer"
  display_name = "Cloud Build Terraform Deployer"
  description  = "Account used by Cloud Build to deploy Cloud Run and Infrastructure"
}

# Grant permissions to the Service Account
# We iterate over a list of roles so we don't repeat code blocks.
resource "google_project_iam_member" "sa_roles" {
  for_each = toset([
    "roles/run.admin",                       # Deploy Cloud Run services
    "roles/iam.serviceAccountUser",          # Attach identities to Cloud Run services
    "roles/storage.admin",                   # Read/Write Terraform state files
    "roles/logging.logWriter",               # Write build logs (CRITICAL)
    "roles/resourcemanager.projectIamAdmin", # Modify IAM policies (if TF manages IAM)
    "roles/secretmanager.secretAccessor",    # Access secrets from Secret Manager
    "roles/secretmanager.viewer",
    "roles/serviceusage.serviceUsageAdmin", # Enable Cloud Build SA to list and enable APIs in the project.
  ])

  project = local.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.cloudbuild_sa.email}"
}

# Cloud Build Trigger
resource "google_cloudbuild_trigger" "deploy_trigger" {
  name        = "deploy-branch"
  description = "Deploys application on push to branch"
  location    = "global"
  project     = local.project_id

  # Link the specific Service Account here
  service_account = google_service_account.cloudbuild_sa.id

  # Connect to your GitHub Repo
  github {
    owner = var.github_org
    name  = var.github_repo
    push {
      branch = "^dev$"
    }
  }

  # Point to your build file
  filename = "/cicd/dev/cloudbuild.yaml"

}

# secrets for the terraform tfvars
resource "google_secret_manager_secret" "tfvars" {
  secret_id = "tfvars"
  project   = local.project_id

  labels = {
    label = "secret-tfvars"
  }

  replication {
    user_managed {
      replicas {
        location = var.default_region
      }
    }
  }
  depends_on = [
    google_project_service.services
  ]
}
