output "project_id" {
  description = "Project where the cid pipeline is established."
  value       = google_project.target_project.project_id
}

output "gcs_bucket_tfstate" {
  description = "Bucket used for storing terraform state the project."
  value       = google_storage_bucket.project_terraform_state.name
}
