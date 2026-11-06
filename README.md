# terraform-gke-iam-impersonate

> [!WARNING]
> This module is **deprecated** and will not receive further updates. Do not use it for new
> clusters. Follow the [migration steps](#migration) below to move to the supported setup.

## Why this module is deprecated

This module enabled GKE service account impersonation using a legacy flow: it created a
`castai_gke_cluster_id` resource that had to be paired with an externally managed
`castai_gke_cluster` configured with `credentials_json = "{}"`. The two resources had an
implicit lifecycle dependency and caused issues in day-to-day Terraform work.

The CAST AI provider (>= 9.14.0) now supports impersonation natively:

- the [`castai_impersonation_service_account`](https://registry.terraform.io/providers/castai/castai/latest/docs/data-sources/impersonation_service_account)
  data source returns the CAST AI service account that performs impersonation;
- [`castai_gke_cluster`](https://registry.terraform.io/providers/castai/castai/latest/docs/resources/gke_cluster)
  accepts `target_service_account_email` and `castai_service_account_email`, replacing the
  `credentials_json = "{}"` workaround.

## Migration

### 0. Prerequisites

- Terraform **>= 1.7** — the examples below use `removed` blocks, which require it.
- CAST AI provider **>= 9.14.0** — pin it before applying the new configuration:
  ```hcl
  terraform {
    required_providers {
      castai = {
        source  = "castai/castai"
        version = ">= 9.14.0"
      }
    }
  }
  ```
- Keep the same `gke_cluster_name` through the migration: the service account name
  (`castai-gke-tf-<sha1 of gke_cluster_name>`) and the `castai_role` ID are derived from
  it. Changing it makes the `moved` blocks below miss their targets.

### 1. Switch the cluster connection to impersonation

In your `castai_gke_cluster` resource (or the `castai/gke-cluster/castai` module), remove
`credentials_json = "{}"` (`gke_credentials = "{}"` in the cluster module) and set the
impersonation fields instead. Where the email values come from depends on which option you
pick in step 2:

```hcl
  target_service_account_email = module.iam-impersonate.client_service_account_email
  castai_service_account_email = module.iam-impersonate.cast_service_account
```

### 2. Replace this module

**Option A — the `castai/gke-iam` module (recommended).**
[castai/terraform-castai-gke-iam](https://github.com/castai/terraform-castai-gke-iam) sets up
all GCP IAM resources required to connect GKE to CAST AI, including impersonation. The idea
is to allow move as many resources as possible to the address under the new module path. You 
may personally adjust and decide what must be moved and what may be recreated. For example, 
you might want to move GCP Service Account but let all the rest get re-created.

```hcl
module "castai_gke_iam" {
  source = "castai/gke-iam/castai"

  project_id       = var.project_id
  gke_cluster_name = var.cluster_name

  authentication_method = "impersonation"
}

# Moving service account works only if the service account name is `castai-gke-tf-<sha1 of gke_cluster_name>`
# If it isn't then either 
# a) use new service account that castai_gke_iam creates
# b) switch to using direct resource (explained further below)
moved {
  from = module.iam_impersonate.google_service_account.client_service_account
  to   = module.castai_gke_iam.google_service_account.castai_service_account
}

moved {
  from = module.iam_impersonate.google_project_iam_custom_role.castai_role
  to   = module.castai_gke_iam.google_project_iam_custom_role.castai_role
}
# google_project_iam_member resource type does not support moving and needs to be recreated.


# It is safe to remove this from the state skipping destroy phase. 
removed {
  from = module.iam_impersonate.castai_gke_cluster_id.cluster_id

  # cluster registration in CAST AI is kept; impersonation settings now live on
  # castai_gke_cluster (step 1)
  lifecycle {
    destroy = false
  }
}
```
Don't forget to update module name to match your configuration.
Update `target_service_account_email` and `castai_service_account_email` to use output of 
castai-gke-iam module.

```hcl
  target_service_account_email = module.castai_gke_iam.target_service_account_email
  castai_service_account_email = module.castai_gke_iam.castai_service_account_email
```

Check `terraform plan` afterwards. It should clearly show `will be removed from the terraform state`
for `removed {}` block and `module.iam-impersonate... has moved to module.castai_gke_iam...`.

**Option B — direct resources.** Manage the GCP IAM resources yourself.

Below is an example of how direct resources configuration could look like.
```hcl
data "castai_impersonation_service_account" "this" {
  provider_type = "gke"
}

resource "google_service_account" "client_service_account" {
  account_id   = "castai-gke-tf-${substr(sha1(var.cluster_name), 0, 8)}" # You may adjust it how you want. This is put here as an exaple only.
  display_name = "Service account to manage ${var.cluster_name} cluster via CAST"
  project      = var.project_id
}

# This enables impersonation.
resource "google_service_account_iam_member" "token_creator" {
  service_account_id = google_service_account.client_service_account.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${data.castai_impersonation_service_account.this.email}"
}

# The rest of permissions configuration. Adjust to what's needed.
data "castai_gke_user_policies" "gke" {
  features = {
    load_balancers_target_backend_pools      = true/false
    load_balancers_unmanaged_instance_groups = true/false
  }
}

resource "google_project_iam_custom_role" "castai_role" {
  role_id     = "castai.gkeAccess.${substr(sha1(var.cluster_name), 0, 8)}.tf"
  title       = "Role to manage GKE cluster via CAST AI"
  description = "Role to manage GKE cluster via CAST AI"
  permissions = data.castai_gke_user_policies.gke.policy
  project     = "PROJECT_ID"
  stage       = "GA"
}

resource "google_project_iam_binding" "castai_binding" {
  project = var.project_id
  role    = google_project_iam_custom_role.castai_role.id
  members = ["serviceAccount:${google_service_account.client_service_account.email}"]
}
```

Additionally grant the permissions from the `castai_gke_user_policies` data source to the
service account, e.g. via a `google_project_iam_custom_role` and
`google_project_iam_member`, as this module did. Then complete step 1 with
`google_service_account.client_service_account.email` and
`data.castai_impersonation_service_account.this.email`.

Direct state manipulation (`terraform state rm` / `terraform state mv`) works as well for
either option.

### 3. Verify

Run `terraform apply` and check the plan. After successful apply check then next
`terraform plan`.

