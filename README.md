# terraform-gke-iam-impersonate

> [!WARNING]
> This module is **deprecated** and will not receive further updates. Do not use it for new
> clusters. For existing installations, refer to the [GKE impersonation documentation in the provider's repo for migration guide](https://github.com/castai/terraform-provider-castai/blob/master/docs/impersonation/gke-impersonation.md) to migrate away from this module.


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
