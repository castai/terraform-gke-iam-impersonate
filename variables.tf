variable "cluster_name" {
  type        = string
  description = "GKE cluster name in GCP project."
}

variable "cluster_region" {
  type        = string
  description = "The region to create the cluster."
}

variable "project_id" {
  type        = string
  description = "GCP project ID in which GKE cluster would be created."
}

variable "service_account_id" {
  type        = string
  description = "Client service account id."
}

variable "compute_manager_project_ids" {
  type        = list(string)
  description = "Projects list for shared sole tenancy nodes"
  default     = []
}

variable "enable_load_balancers_unmanaged_instance_groups_permissions" {
  description = "Enable or disable GKE load balancer unmanaged instance groups permissions"
  type        = bool
  default     = false
}

variable "enable_load_balancers_target_backend_pools_permissions" {
  description = "Enable or disable GKE load balancer target backend pools permissions"
  type        = bool
  default     = false
}
