# Defaults are the demo profile that fits the 20 USD budget (ADR 0004).
# A production profile would only change these values, for example:
#   sku_tier   = "Standard"
#   zones      = ["1", "2", "3"]
#   system_pool = { vm_size = "Standard_D2s_v5", node_count = 3 }
#   apps_pool   = { vm_size = "Standard_D4s_v5", node_count = 3 }

variable "kubernetes_version" {
  description = "Minor version only; every rebuild gets the latest patch."
  type        = string
  default     = "1.36"
}

variable "sku_tier" {
  description = "Control plane tier: Free (no SLA) or Standard (SLA, about 0.10 USD/h)."
  type        = string
  default     = "Free"

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.sku_tier)
    error_message = "sku_tier must be Free, Standard or Premium."
  }
}

variable "zones" {
  description = "Availability zones for both node pools. Empty = no zone pinning."
  type        = list(string)
  default     = []
}

variable "system_pool" {
  description = "System node pool: only kube-system / critical add-ons (tainted CriticalAddonsOnly)."
  type = object({
    vm_size    = string
    node_count = number
  })
  default = {
    vm_size    = "Standard_B2s" # 2 vCPU, 4 GiB
    node_count = 1
  }
}

variable "apps_pool" {
  description = "User node pool: platform components (ArgoCD, ingress, ...) and the services."
  type = object({
    vm_size    = string
    node_count = number
  })
  default = {
    vm_size    = "Standard_B2ms" # 2 vCPU, 8 GiB
    node_count = 1
  }
}
