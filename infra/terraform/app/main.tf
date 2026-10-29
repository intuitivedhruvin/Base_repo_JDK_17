locals {
  runtime_sa = "trebol-run@${var.project_id}.iam.gserviceaccount.com"
}

# ---- Secrets ----
resource "random_password" "db" {
  length  = 32
  special = false
}

resource "random_password" "jwt" {
  length  = 96
  special = false
}

resource "google_secret_manager_secret" "db_password" {
  secret_id = "trebol-db-password"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db.result
}

resource "google_secret_manager_secret" "jwt" {
  secret_id = "trebol-jwt-secret"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "jwt" {
  secret      = google_secret_manager_secret.jwt.id
  secret_data = random_password.jwt.result
}

# ---- Cloud SQL (MySQL 8) ----
# Public IP with no authorized networks: only reachable through the
# IAM-authenticated Cloud SQL Auth Proxy, so no VPC setup is needed
resource "google_sql_database_instance" "main" {
  name                = "trebol-mysql"
  database_version    = "MYSQL_8_0"
  region              = var.region
  deletion_protection = var.deletion_protection

  settings {
    tier              = var.db_tier
    availability_type = var.db_availability_type
    disk_autoresize   = true

    backup_configuration {
      enabled            = true
      binary_log_enabled = true
    }

    ip_configuration {
      ipv4_enabled = true
      ssl_mode     = "ENCRYPTED_ONLY"
    }

    database_flags {
      name  = "max_connections"
      value = tostring(var.db_max_connections)
    }

    insights_config {
      query_insights_enabled = true
    }
  }
}

resource "google_sql_database" "trebol" {
  name     = "trebol"
  instance = google_sql_database_instance.main.name
}

resource "google_sql_user" "trebol" {
  name     = "trebol"
  instance = google_sql_database_instance.main.name
  password = random_password.db.result
}

# ---- Cloud Run ----
resource "google_cloud_run_v2_service" "api" {
  name                 = "trebol-api"
  location             = var.region
  ingress              = "INGRESS_TRAFFIC_ALL"
  deletion_protection  = false
  invoker_iam_disabled = true # public API without an allUsers IAM binding

  template {
    service_account                  = local.runtime_sa
    max_instance_request_concurrency = var.concurrency
    timeout                          = "30s"

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    containers {
      name       = "app"
      image      = var.image
      depends_on = ["cloud-sql-proxy"]

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "2"
          memory = "2Gi"
        }
        cpu_idle          = false
        startup_cpu_boost = true
      }

      env {
        name  = "SPRING_PROFILES_ACTIVE"
        value = "mysql"
      }
      env {
        name  = "DB_URL"
        value = "jdbc:mariadb://127.0.0.1:3306/${google_sql_database.trebol.name}"
      }
      env {
        name  = "DB_USER"
        value = google_sql_user.trebol.name
      }
      env {
        name  = "DB_POOL_SIZE"
        value = tostring(var.db_pool_size)
      }
      env {
        name  = "DB_SEED_MODE"
        value = var.db_seed_mode
      }
      env {
        name  = "CORS_ALLOWED_ORIGINS"
        value = var.cors_allowed_origins
      }
      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_password.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "JWT_SECRET_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.jwt.secret_id
            version = "latest"
          }
        }
      }

      startup_probe {
        http_get {
          path = "/actuator/health/readiness"
          port = 8080
        }
        initial_delay_seconds = 10
        period_seconds        = 5
        timeout_seconds       = 3
        failure_threshold     = 30
      }

      liveness_probe {
        http_get {
          path = "/actuator/health/liveness"
          port = 8080
        }
        period_seconds    = 15
        timeout_seconds   = 3
        failure_threshold = 3
      }
    }

    # Sidecar: the MariaDB driver talks plain TCP to the proxy on localhost
    containers {
      name  = "cloud-sql-proxy"
      image = "gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.14.1"
      args = [
        "--port=3306",
        "--health-check",
        "--http-address=0.0.0.0",
        "--http-port=9801",
        "--structured-logs",
        google_sql_database_instance.main.connection_name,
      ]

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle = false
      }

      startup_probe {
        http_get {
          path = "/startup"
          port = 9801
        }
        period_seconds    = 2
        failure_threshold = 30
      }
    }
  }

  lifecycle {
    # CI owns the image and revision metadata after the first apply
    ignore_changes = [
      template[0].containers[0].image,
      template[0].revision,
      client,
      client_version,
    ]
  }

  depends_on = [
    google_secret_manager_secret_version.db_password,
    google_secret_manager_secret_version.jwt,
  ]
}
