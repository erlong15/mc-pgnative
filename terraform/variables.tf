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

variable "wal_retention_days" {
  type        = number
  description = "Количество дней хранения WAL файлов"
  default     = 30
  
  validation {
    condition     = var.wal_retention_days >= 7
    error_message = "WAL retention must be at least 7 days for PITR."
  }
}

variable "full_backup_retention_days" {
  type        = number
  description = "Количество дней хранения полных бэкапов"
  default     = 90
  
  validation {
    condition     = var.full_backup_retention_days >= var.wal_retention_days
    error_message = "Full backup retention must be greater than or equal to WAL retention."
  }
}

variable "kms_key_id" {
  type        = string
  description = "KMS key ID для шифрования (опционально)"
  default     = ""
}

variable "force_destroy_bucket" {
  type        = bool
  description = "Удалять бакет с данными при уничтожении ресурса"
  default     = false
}

variable "domain_name" {
  type        = string
  description = "Доменное имя для CORS (если нужен доступ через браузер)"
  default     = ""
}

variable "bucket_name_suffix" {
  type        = string
  description = "Суффикс для имени бакета"
  default     = ""
}

variable "project_name" {
  type        = string
  description = "Название проекта"
  default     = "myproject"
}

variable "environment" {
  type        = string
  description = "Окружение (dev, staging, production)"
  default     = "production"
  
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, production."
  }
}


variable "pg_cluster_name" {
  type        = string
  description = "Имя PostgreSQL кластера PgNative"
  default     = "cluster-example"
}

variable "admin_login" {
  type = string
  default = "atsykunov15@yandex.ru"
}