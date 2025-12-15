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
  project_id    = module.gcp_project_setup.project_id
  location      = var.default_region
  service_name  = var.service_name
  gar_repo_name = "prj-containers" #container artifact registry repository
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
