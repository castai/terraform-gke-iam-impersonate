locals {
  compute_manager_project_ids = var.compute_manager_project_ids
}

data "castai_gke_user_policies" "gke" {
  features = {
    load_balancers_target_backend_pools      = var.enable_load_balancers_target_backend_pools_permissions,
    load_balancers_unmanaged_instance_groups = var.enable_load_balancers_unmanaged_instance_groups_permissions
  }
}

resource "google_service_account" "client_service_account" {
  account_id   = var.service_account_id
  display_name = "Service account to manage ${var.cluster_name} cluster via CAST"
  project      = var.project_id
}

resource "google_project_iam_custom_role" "castai_role" {
  role_id     = "castai.gkeAccess.${substr(sha1(var.cluster_name), 0, 8)}.tf"
  title       = "Role to manage GKE cluster via CAST AI"
  description = "Role to manage GKE cluster via CAST AI"
  permissions = data.castai_gke_user_policies.gke.policy
  project     = var.project_id
  stage       = "GA"
}

resource "google_project_iam_custom_role" "compute_manager_role" {
  for_each = toset(local.compute_manager_project_ids)

  project = each.key

  role_id     = "castai.gkeAccess.${substr(sha1(each.key), 0, 8)}.tf"
  title       = "Role to manage GKE compute resources via CAST AI"
  description = "Role to manage GKE compute resources via CAST AI"
  permissions = data.castai_gke_user_policies.gke.policy
  stage       = "GA"
}

resource "google_project_iam_binding" "compute_manager_binding" {
  project = var.project_id
  role    = google_project_iam_custom_role.castai_role.name
  members = [google_service_account.client_service_account.member]
}

# Configure GKE cluster and obtain the castai service account.
resource "castai_gke_cluster_id" "cluster_id" {
  name                   = var.cluster_name
  location               = var.cluster_region
  project_id             = var.project_id
  client_service_account = google_service_account.client_service_account.email
}

# Grant the roles/iam.serviceAccountTokenCreator role to the CASTAI_SERVICE_ACCOUNT
resource "google_service_account_iam_member" "token_creator_binding" {
  service_account_id = google_service_account.client_service_account.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${castai_gke_cluster_id.cluster_id.cast_service_account}"

  depends_on = [castai_gke_cluster_id.cluster_id]
}

# Grant the roles/iam.serviceAccountUser role to the CASTAI_SERVICE_ACCOUNT with a specific condition
resource "google_service_account_iam_member" "impersonation_user_binding" {
  service_account_id = google_service_account.client_service_account.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${castai_gke_cluster_id.cluster_id.cast_service_account}"

  condition {
    title       = "SpecificServiceAccountCondition"
    description = "Allow impersonation only for CASTAI_SERVICE_ACCOUNT"
    expression  = "request.auth.claims.email == \"${castai_gke_cluster_id.cluster_id.cast_service_account}\""
  }

  depends_on = [castai_gke_cluster_id.cluster_id]
}

# Grant the roles/iam.serviceAccountUser role to the CLIENT_SERVICE_ACCOUNT
resource "google_project_iam_member" "service_account_user" {
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = google_service_account.client_service_account.member
}

// service_account
resource "time_sleep" "wait_3_minutes" {
  depends_on = [
    google_service_account.client_service_account,
    google_service_account_iam_member.token_creator_binding,
    google_service_account_iam_member.impersonation_user_binding,
    google_project_iam_member.service_account_user,
  ]

  create_duration = "180s"
}