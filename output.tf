output "client_service_account_email" {
  value = google_service_account.client_service_account.email
}

output "client_service_account_name" {
  value = google_service_account.client_service_account.name
}

output "cast_service_account" {
  value = castai_gke_cluster_id.cluster_id.cast_service_account
}