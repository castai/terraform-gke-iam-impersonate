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
resource "castai_gke_cluster" "this" {
  # ... existing configuration, without credentials_json = "{}" ...

  target_service_account_email = # see step 2
  castai_service_account_email = # see step 2
}
```

### 2. Replace this module

**Option A — the `castai/gke-iam` module (recommended).**
[castai/terraform-castai-gke-iam](https://github.com/castai/terraform-castai-gke-iam) sets up
all GCP IAM resources required to connect GKE to CAST AI, including impersonation:

```hcl
module "castai_gke_iam" {
  source = "castai/gke-iam/castai"

  project_id       = var.project_id
  gke_cluster_name = var.cluster_name

  authentication_method = "impersonation"
}

moved {
  from = module.service_account_impersonation.google_service_account.client_service_account
  to   = module.castai_gke_iam.google_service_account.castai_service_account[0]
}

moved {
  from = module.service_account_impersonation.google_service_account_iam_member.token_creator_binding
  to   = module.castai_gke_iam.google_service_account_iam_member.castai_token_creator[0]
}

moved {
  from = module.service_account_impersonation.google_project_iam_member.service_account_user
  to   = module.castai_gke_iam.google_project_iam_member.project["roles/iam.serviceAccountUser"]
}

moved {
  from = module.service_account_impersonation.google_project_iam_custom_role.castai_role
  to   = module.castai_gke_iam.google_project_iam_custom_role.castai_role
}

moved {
  from = module.service_account_impersonation.google_project_iam_custom_role.compute_manager_role
  to   = module.castai_gke_iam.google_project_iam_custom_role.compute_manager_role
}

removed {
  from = module.service_account_impersonation.castai_gke_cluster_id.cluster_id

  # cluster registration in CAST AI is kept; impersonation settings now live on
  # castai_gke_cluster (step 1)
  lifecycle {
    destroy = false
  }
}

removed {
  from = module.service_account_impersonation.google_service_account_iam_member.impersonation_user_binding

  lifecycle {
    destroy = true
  }
}

removed {
  from = module.service_account_impersonation.google_project_iam_binding.compute_manager_binding

  # kept so there is no permission gap: castai/gke-iam re-grants the same role to the
  # same member in the same apply
  lifecycle {
    destroy = false
  }
}

removed {
  from = module.service_account_impersonation.time_sleep.wait_3_minutes

  lifecycle {
    destroy = true
  }
}
```

> [!NOTE]
> Adjust the module path `module.service_account_impersonation` in the `moved`/`removed`
> blocks above to the name of this module's instance in your configuration.

The `moved` block for the service account requires the name `castai/gke-iam` expects —
`castai-gke-tf-<sha1 of gke_cluster_name>`. If yours differs, drop that block, let the
module create its own account and remove the old one from state instead. Drop the
`compute_manager_role` `moved` block as well if you never set
`compute_manager_project_ids`. The `moved` targets under `google_project_iam_member.project`
exist only when the module's `service_accounts_unique_ids` input is left empty (the
default); if you set it, the module grants on `scoped_project` instead and you must manage
those grants yourself.

The module exports `target_service_account_email` and `castai_service_account_email`, which
complete step 1:

```hcl
resource "castai_gke_cluster" "this" {
  # ... existing configuration ...

  target_service_account_email = module.castai_gke_iam.target_service_account_email
  castai_service_account_email = module.castai_gke_iam.castai_service_account_email
}
```

For a phased migration where the cluster keeps its key-based connection while the
impersonation IAM is prepared, set `authentication_method_migration = "prepare"` on the
module first, then flip `authentication_method = "impersonation"` and update the cluster
resource once the plan shows only the expected IAM changes.

**Option B — direct resources.** Manage the GCP IAM resources yourself and use only the
provider data source. The mapping in the [appendix](#appendix-what-maps-to-what) applies
without the module addresses:

```hcl
data "castai_impersonation_service_account" "this" {
  provider_type = "gke"
}

resource "google_service_account" "client_service_account" {
  account_id   = "castai-gke-tf-${substr(sha1(var.cluster_name), 0, 8)}"
  display_name = "Service account to manage ${var.cluster_name} cluster via CAST"
  project      = var.project_id
}

resource "google_service_account_iam_member" "token_creator" {
  service_account_id = google_service_account.client_service_account.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${data.castai_impersonation_service_account.this.email}"
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

The first plan after steps 1-2 should show:

- moves of the service account, the token creator binding, the
  `roles/iam.serviceAccountUser` project grant and the two custom roles — no destroy/create
  for them;
- one create for the re-created compute-manager grant;
- removals of `cluster_id`, `time_sleep` and the impersonation-user binding
  (only the binding is actually destroyed).

After applying, a second `terraform plan` must be empty, and the cluster should show as
connected in the CAST AI console.

## Appendix: what maps to what

The table below maps every resource of this module to its counterpart in `castai/gke-iam` —
what is dropped, what is reused, and what must be moved or re-created:

| Resource in this module | After migration |
| --- | --- |
| `castai_gke_cluster_id.cluster_id` | Superseded by the impersonation settings on `castai_gke_cluster` — no replacement. |
| `google_service_account.client_service_account` | `castai/gke-iam` `google_service_account.castai_service_account` — the same account when named `castai-gke-tf-<sha1 of gke_cluster_name>`, otherwise migrated out of the module. |
| `google_service_account_iam_member.token_creator_binding` | `castai/gke-iam` `google_service_account_iam_member.castai_token_creator` — still required; move or re-create. The always-true condition is dropped either way. |
| `google_service_account_iam_member.impersonation_user_binding` | Not required for impersonation — destroy. |
| `google_project_iam_member.service_account_user` | `castai/gke-iam` `google_project_iam_member.project["roles/iam.serviceAccountUser"]` — move or re-create. |
| `google_project_iam_custom_role.castai_role` | `castai/gke-iam` `google_project_iam_custom_role.castai_role` — identical `role_id`, move. |
| `google_project_iam_custom_role.compute_manager_role` | `castai/gke-iam` `google_project_iam_custom_role.compute_manager_role` — identical, move. |
| `google_project_iam_binding.compute_manager_binding` | `castai/gke-iam` project-level grant `google_project_iam_member.project["projects/<project_id>/roles/<castai_role_id>"]` — re-create, the resource type differs. |
| `time_sleep.wait_3_minutes` | No replacement — dropped. `castai/gke-iam` orders its outputs on the IAM bindings instead. |
| `data.google_project.project` | Unused — dropped with the module. |

- `castai/gke-iam` creates the service account and the project-level grants only with
  `create_service_account = true` (the default). With `create_service_account = false` it
  manages only the custom roles, the compute-manager bindings and the token creator
  binding on the existing account — keep the project-level grants yourself.
- The `enable_load_balancers_*` toggles have no `castai/gke-iam` equivalent; pass explicit
  `castai_role_permissions` / `compute_manager_permissions` instead.
- If you use `compute_manager_project_ids`, the per-project compute-manager bindings are
  new grants — `castai/gke-iam` creates them.
