variable "cloud_id" { 
  type = string
  default =  "b1gdooc1qviqeqtios79"
}
variable "folder_id" { 
  type = string 
  default = "b1glnat8n1a6jgo3a6fs"
}
variable "zone" { 
  type = string
  default = "ru-central1-a"
}
variable "cluster_name" { 
  type = string  
  default = "vault-lab" 
  }

variable "public_access" { 
  type = bool 
  default = true 
}

variable "default_algorithm" {
  description = "Encryption algorithm to be used for this key"
  type        = string
  default     = "AES_256" # AES_128, AES_192, AES_256
}

variable "rotation_period" {
  description = "Interval between automatic rotations. To disable automatic rotation, set this parameter equal to null"
  type        = string
  default     = "8760h" # equal to 1 year
}

