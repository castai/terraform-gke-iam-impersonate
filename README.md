# Terraform module to manage service account impersonation

Module gets region, cluster name, project and client service account id as input 
and creates a service account impersonation role binding. 

Outputs client service account name and email amd cast created service account
email.

## Usage

```
module "service_account_impersonation" {
  source = "castai/gke-iam-impersonate/castai"

  region = "us-central1"
  cluster_name = "my-cluster"
  project = "my-project"
  client_service_account_id = "client-service-account-unique-string"
}
```