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
  environment         = "prod"
  branch_name         = "^main$"
  cloudbuild_filename = "/cicd/prod/cloudbuild.yaml"
}
