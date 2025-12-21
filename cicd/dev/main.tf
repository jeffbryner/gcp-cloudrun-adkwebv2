module "gcp_project_setup" {
  source          = "../modules/gcp_project_setup"
  environment     = "dev"
  project_name    = var.project_name
  default_region  = var.default_region
  org_id          = var.org_id
  folder_id       = var.folder_id
  billing_account = var.billing_account
  project_labels  = var.project_labels

}

data "external" "git_sha" {
  program = ["sh", "-c", "echo \"{\\\"sha\\\": \\\"$(git rev-parse --short HEAD)\\\"}\""]
}

locals {
  project_id         = module.gcp_project_setup.project_id
  location           = var.default_region
  service_name       = var.service_name
  cloudbuild_sa      = "serviceAccount:${module.gcp_project_setup.cloudbuild_sa.email}"
  gar_repo_name      = "prj-containers" #container artifact registry repository
  art_bucket_name    = format("bkt-%s-%s", "artifacts", local.project_id)
  git_sha_tag        = data.external.git_sha.result.sha
  adk_web_hash       = sha1(join("", [for f in fileset(path.root, "../../src/container/**") : filesha1(f)]))
  adk_web_image_name = "${local.location}-docker.pkg.dev/${local.project_id}/${local.gar_repo_name}/adk_web:${local.adk_web_hash}"
}


resource "terraform_data" "adk_web_build" {
  input = local.adk_web_image_name # the image name with tag

  triggers_replace = [
    # Only triggers when actual code changes
    # use the hash as the image tag as well
    # to ensure cloud run gets updated image
    local.adk_web_hash
  ]

  provisioner "local-exec" {
    # We use a cloudbuild config,
    # but pass in a specific Dockerfile and Image Name
    # to allow one build with multiple docker images/cloud run services
    # if needed (one for adk web, one for agent api, etc)
    command = <<EOT
        gcloud builds submit ../../src/container \
          --config=../../src/container/cloudbuild.yaml \
          --substitutions=_DOCKERFILE=adk.web.Dockerfile,_IMAGE=${self.input} \
          --service-account=${module.gcp_project_setup.cloudbuild_sa.id}          
      EOT
  }
}


# Cloud Build Trigger
# If using developer connect, you need to set up the connection first in GCP console
# and likely will need to create the trigger manually as well
# resource "google_cloudbuild_trigger" "deploy_trigger" {
#   name        = "deploy-branch"
#   description = "Deploys application on push to branch"
#   location    = var.default_region
#   project     = local.project_id

#   # Link the specific Service Account here
#   service_account = local.cloudbuild_sa

#   # Connect to your GitHub Repo (github or developer_connect stanza)
#   https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloudbuild_trigger#example-usage---cloudbuild-trigger-developer-connect-push
#   github {
#     owner = var.github_org
#     name  = var.github_repo
#     push {
#       branch = var.branch_name
#     }
#   }
# OR
#   developer_connect_event_config {
#     git_repository_link = "projects/cryptic-tower-286020/locations/us-central1/connections/prod-bbs-push/gitRepositoryLinks/cbprob-prod-us-central1-push1"
#     push {
#       branch = "main"
#     }
#   }
#   filename = "cloudbuild.yaml"
# }



#   # Point to your build file
#   filename = var.cloudbuild_filename

# }



# create a bucket for cloudbuild artifacts
resource "google_storage_bucket" "cloudbuild_artifacts" {
  project                     = local.project_id
  name                        = local.art_bucket_name
  location                    = local.location
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

# if needed set a project policy to allow allUsers invoke
# will need to enable the org policy api first and grant the service account permissions
# https://cloud.google.com/run/docs/securing/iam#allow_unauthenticated_access
# resource "google_project_organization_policy" "services_policy" {
#   project    = local.project_id
#   constraint = "iam.allowedPolicyMemberDomains"

#   list_policy {
#     allow {
#       all = true
#     }
#   }
# }


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
        #image = "${local.location}-docker.pkg.dev/${local.project_id}/${local.gar_repo_name}/${local.service_name}"
        image = terraform_data.adk_web_build.output

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
