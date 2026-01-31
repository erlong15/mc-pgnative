# 1. Создание сервисного аккаунта для управления бэкапами
resource "yandex_iam_service_account" "pg_backup_sa" {
  name        = "pg-backup-sa"
  description = "Service account for PostgreSQL backups to Object Storage"
  folder_id   = var.folder_id
}


# 2. Роли для сервисного аккаунта
resource "yandex_resourcemanager_folder_iam_member" "editor" {
  folder_id = var.folder_id
  role      = "storage.editor"
  member    = "serviceAccount:${yandex_iam_service_account.pg_backup_sa.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "viewer" {
  folder_id = var.folder_id
  role      = "storage.viewer"
  member    = "serviceAccount:${yandex_iam_service_account.pg_backup_sa.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "config_viewer" {
  folder_id = var.folder_id
  role      = "kms.keys.encrypterDecrypter"
  member    = "serviceAccount:${yandex_iam_service_account.pg_backup_sa.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "storage_admin" {
  folder_id = var.folder_id
  role      = "storage.admin"  # Нужно для управления бакетами
  member    = "serviceAccount:${yandex_iam_service_account.pg_backup_sa.id}"
}


resource "yandex_storage_bucket_iam_binding" "pg_bucket_configurer" {
  bucket  = yandex_storage_bucket.pg_backup_bucket.bucket
  role    = "storage.admin"
  members = [
              "userAccount:${data.yandex_iam_user.current.id}"
            ]
}

resource "yandex_storage_bucket_iam_binding" "pg_bucket_admins" {
  bucket  = yandex_storage_bucket.pg_backup_bucket.bucket
  role    = "storage.configurer"
  members = [
              "userAccount:${data.yandex_iam_user.current.id}"
            ]
}

# Если используете KMS, добавьте:
resource "yandex_resourcemanager_folder_iam_member" "kms_user" {
  count = var.kms_key_id != "" ? 1 : 0
  
  folder_id = var.folder_id
  role      = "kms.user"
  member    = "serviceAccount:${yandex_iam_service_account.pg_backup_sa.id}"
}


# 3. Создание статических ключей доступа
resource "yandex_iam_service_account_static_access_key" "pg_backup_keys" {
  service_account_id = yandex_iam_service_account.pg_backup_sa.id
  description        = "Static access key for PostgreSQL backup operations"
}

# 4. Создание бакета для бэкапов PostgreSQL
# backup_bucket.tf
# 4. Создание бакета для бэкапов PostgreSQL
resource "yandex_storage_bucket" "pg_backup_bucket" {
  bucket     = "pg-backup-${var.project_name}-${var.environment}"
  folder_id  = var.folder_id
  
  # Опции жизненного цикла для автоматического управления объектами
  lifecycle_rule {
    id      = "wal-retention"
    enabled = true
    
    # Переместить старые WAL в холодное хранилище
    transition {
      days          = 7
      storage_class = "COLD"
    }
    
    # Удалить очень старые WAL
    expiration {
      days = var.wal_retention_days
    }
    
    filter {
      prefix = "wal/"
    }
  }
  
  lifecycle_rule {
    id      = "full-backup-retention"
    enabled = true
    
    # Полные бэкапы храним в STANDARD 14 дней
    transition {
      days          = 14
      storage_class = "COLD"
    }
    
    # Удалить через указанное количество дней
    expiration {
      days = var.full_backup_retention_days
    }
    
    filter {
      prefix = "data/"
    }
  }
  
  # Версионирование для защиты от случайного удаления
  versioning {
    enabled = true
  }
  
  # Шифрование на стороне сервера
  dynamic "server_side_encryption_configuration" {
    for_each = var.kms_key_id != "" ? [1] : []
    
    content {
      rule {
        apply_server_side_encryption_by_default {
          kms_master_key_id = var.kms_key_id
          sse_algorithm     = "aws:kms"
        }
      }
    }
  }
  
  # Для шифрования AES256 (без KMS) - не указываем server_side_encryption_configuration
  # Yandex Cloud по умолчанию использует AES256
  
  # Корзина для защищенного удаления
  force_destroy = var.force_destroy_bucket


  # Политика для публичного доступа (обычно отключаем)
  anonymous_access_flags {
    read        = false
    list        = false
    config_read = false
  }
  
  # Теги для удобства поиска и учета
  tags = {
    Name        = "PostgreSQL Backups"
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Component   = "Database"
    Retention   = "${var.full_backup_retention_days}days"
  }
}

# 4.1. Управление правами доступа через yandex_storage_bucket_grant
resource "yandex_storage_bucket_grant" "backup_bucket_grants" {
  bucket = yandex_storage_bucket.pg_backup_bucket.bucket
  
  # Права для сервисного аккаунта (только FULL_CONTROL, READ или WRITE)
  grant {
    type        = "CanonicalUser"
    id          = yandex_iam_service_account.pg_backup_sa.id
    permissions = ["FULL_CONTROL"]  # Используем только FULL_CONTROL
  }

  grant {
    type        = "CanonicalUser"
    id          = data.yandex_iam_user.current.id
    permissions = ["FULL_CONTROL"]  # Используем только FULL_CONTROL
  }  
}


# 5. Политика бакета (Bucket Policy) для дополнительной безопасности
data "yandex_iam_user" "current" {
    login = var.admin_login
}

resource "yandex_storage_bucket_policy" "backup_policy" {
  bucket = yandex_storage_bucket.pg_backup_bucket.bucket
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowServiceAccount"
        Effect = "Allow"
        Principal = {
          "CanonicalUser": yandex_iam_service_account.pg_backup_sa.id
        }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetObjectVersion"
        ]
        Resource = [
          "arn:aws:s3:::${yandex_storage_bucket.pg_backup_bucket.bucket}",
          "arn:aws:s3:::${yandex_storage_bucket.pg_backup_bucket.bucket}/*"
        ]
      },
      {
        Sid    = "AllowMe"
        Effect = "Allow"
        Principal = {
          "CanonicalUser": "${data.yandex_iam_user.current.id}"
        }
        Action = "s3:*"
        Resource = [
          "arn:aws:s3:::${yandex_storage_bucket.pg_backup_bucket.bucket}",
          "arn:aws:s3:::${yandex_storage_bucket.pg_backup_bucket.bucket}/*"
        ]
      }
    ]
  })
}

# 6. Создание папок внутри бакета
resource "yandex_storage_object" "wal_folder" {
  bucket = yandex_storage_bucket.pg_backup_bucket.bucket
  key    = "wal/"
  source = "/dev/null"  # Создаем пустую папку
}

resource "yandex_storage_object" "data_folder" {
  bucket = yandex_storage_bucket.pg_backup_bucket.bucket
  key    = "data/"
  source = "/dev/null"
}

resource "yandex_storage_object" "clusters_folder" {
  bucket = yandex_storage_bucket.pg_backup_bucket.bucket
  key    = "clusters/"
  source = "/dev/null"
}


# 10. Output значения для использования в других модулях
output "bucket_name" {
  value       = yandex_storage_bucket.pg_backup_bucket.bucket
  description = "Имя созданного бакета для бэкапов"
}

output "bucket_endpoint" {
  value       = "https://storage.yandexcloud.net/${yandex_storage_bucket.pg_backup_bucket.bucket}"
  description = "Endpoint для доступа к бакету"
}

output "service_account_id" {
  value       = yandex_iam_service_account.pg_backup_sa.id
  description = "ID сервисного аккаунта для бэкапов"
}

output "access_key_id" {
  value       = yandex_iam_service_account_static_access_key.pg_backup_keys.access_key
  description = "Access Key ID для S3 API"
  sensitive   = true
}

output "secret_access_key" {
  value       = yandex_iam_service_account_static_access_key.pg_backup_keys.secret_key
  description = "Secret Access Key для S3 API"
  sensitive   = true
}

output "backup_path" {
  value       = "s3://${yandex_storage_bucket.pg_backup_bucket.bucket}/${var.pg_cluster_name}/"
  description = "Путь для бэкапов в формате S3 URI"
}