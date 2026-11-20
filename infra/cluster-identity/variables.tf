variable "admin_object_id" {
  description = "Entra object ID of the human cluster admin (az ad signed-in-user show --query id -o tsv)."
  type        = string
}
