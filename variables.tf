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

variable "castai_role_permissions" {
  description = "A set of permissions that will be granted to CAST AI role used by central system"
  type        = list(string)
  default     = []
}

variable "compute_manager_permissions" {
  description = "A set of permissions that will be granted to compute manager role"
  type        = list(string)
  default     = []
}

variable "compute_manager_project_ids" {
  type        = list(string)
  description = "Projects list for shared sole tenancy nodes"
  default     = []
}