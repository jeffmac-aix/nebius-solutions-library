variable "number_of_hosts" {
  type        = number
  description = "Number of GPU hosts to test"
  default     = 0
}

variable "node_selector" {
  description = "Select the GPU pool for NCCL workers."
  type        = map(string)
  default     = {}
}

variable "tolerations" {
  description = "Tolerations for the selected GPU pool."
  type = list(object({
    key      = string
    operator = string
    value    = string
    effect   = string
  }))
  default = []
}
