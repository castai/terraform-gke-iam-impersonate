# Terraform module to manage service account impersonation

Module gets region, cluster name, project and client service account id as input 
and creates a service account impersonation role binding. 

Outputs client service account name and email amd cast created service account
email.