variable "alert_email" {
  description = "E-mail address that receives budget alerts. Set via terraform.tfvars (gitignored) or TF_VAR_alert_email."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email must be a valid e-mail address."
  }
}
