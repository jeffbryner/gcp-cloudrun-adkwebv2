module "gcp_project_setup" {
  source = "../modules/gcp_project_setup"

  project_name        = var.project_name
  github_org          = var.github_org
  github_repo         = var.github_repo
  default_region      = var.default_region
  org_id              = var.org_id
  folder_id           = var.folder_id
  billing_account     = var.billing_account
  project_labels      = var.project_labels
  environment         = "dev"
  branch_name         = "^dev$"
  cloudbuild_filename = "/cicd/dev/cloudbuild.yaml"
}

locals {
  project_id      = module.gcp_project_setup.project_id
  location        = var.default_region
  service_name    = var.service_name
  cloudbuild_sa   = "serviceAccount:${module.gcp_project_setup.cloudbuild_sa.email}"
  gar_repo_name   = "prj-containers" #container artifact registry repository
  art_bucket_name = format("bkt-%s-%s", "artifacts", local.project_id)
}

# trigger builds on file changes in the container directory
resource "null_resource" "cloudbuild_cloudrun_container" {
  triggers = {
    dir_sha1 = sha1(join("", [for f in fileset(path.root, "../../src/container/**") : filesha1(f)]))
  }


  provisioner "local-exec" {
    command = <<EOT
      gcloud builds submit ../../src/container/ --project ${module.gcp_project_setup.project_id}  --substitutions=_SERVICE_NAME=${var.service_name} --config=../../src/container/cloudbuild.yaml
  EOT
  }
}

# create a bucket for cloudbuild artifacts
resource "google_storage_bucket" "cloudbuild_artifacts" {
  project                     = local.project_id
  name                        = local.art_bucket_name
  location                    = var.default_region
  uniform_bucket_level_access = true
  force_destroy               = true
  versioning {
    enabled = true
  }
}

resource "google_storage_bucket_iam_member" "cloudbuild_artifacts_iam" {
  bucket = google_storage_bucket.cloudbuild_artifacts.name
  role   = "roles/storage.admin"
  member = local.cloudbuild_sa
}

resource "google_artifact_registry_repository" "image-repo" {
  provider = google-beta
  project  = local.project_id

  location      = local.location
  repository_id = local.gar_repo_name
  description   = "Docker repository for images used by Cloud Build"
  format        = "DOCKER"
}

resource "google_artifact_registry_repository_iam_member" "terraform-image-iam" {
  provider = google-beta
  project  = local.project_id

  location   = google_artifact_registry_repository.image-repo.location
  repository = google_artifact_registry_repository.image-repo.name
  role       = "roles/artifactregistry.writer"
  member     = local.cloudbuild_sa
  depends_on = [
    google_artifact_registry_repository.image-repo
  ]
}

# set a project policy to allow allUsers invoke
resource "google_project_organization_policy" "services_policy" {
  project    = local.project_id
  constraint = "iam.allowedPolicyMemberDomains"

  list_policy {
    allow {
      all = true
    }
  }
}


# dedicated service account for our cloudrun service
# so we don't use the default compute engine service account
resource "google_service_account" "cloudrun_service_identity" {
  project    = local.project_id
  account_id = "${local.service_name}-svc-act"
}

resource "google_cloud_run_service" "default" {
  name                       = local.service_name
  location                   = local.location
  project                    = local.project_id
  autogenerate_revision_name = true

  template {
    spec {
      service_account_name = google_service_account.cloudrun_service_identity.email
      containers {
        image = "${local.location}-docker.pkg.dev/${local.project_id}/${local.gar_repo_name}/${local.service_name}"

      }
    }
  }

}


data "google_iam_policy" "noauth" {
  binding {
    role = "roles/run.invoker"
    members = [
      "allUsers",
    ]
  }
}


resource "google_cloud_run_service_iam_policy" "noauth" {
  location = google_cloud_run_service.default.location
  project  = local.project_id
  service  = google_cloud_run_service.default.name

  policy_data = data.google_iam_policy.noauth.policy_data
}


# allow the  service account to access AI
resource "google_project_iam_member" "ai_access" {
  provider = google-beta
  project  = local.project_id
  role     = "roles/aiplatform.user"
  member   = "serviceAccount:${google_service_account.cloudrun_service_identity.email}"
}
