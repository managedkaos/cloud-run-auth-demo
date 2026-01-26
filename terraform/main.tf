# --- 0. Variables ---
variable "project_id" {
  type        = string
  description = "The GCP Project ID (must be globally unique)"
}

variable "name" {
  type        = string
  description = "The base name to use for the cloud run instance"
}

variable "region" {
  type        = string
  description = "The GCP region where resources are deployed"
}

# --- 1. Provider & Version Setup ---
# For the gcs backend, you can set the GOOGLE_STORAGE_BUCKET
# environment variable, which the backend configuration will read.
# export GOOGLE_STORAGE_BUCKET="terraform-state-bucket-name"
terraform {
  backend "gcs" {
    prefix = "terraform/state"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 7.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project               = var.project_id
  region                = var.region
  user_project_override = true
}


# --- 2. Enable Required APIs ---
resource "google_project_service" "services" {
  for_each = toset([
    "run.googleapis.com",             # Cloud Run
    "firestore.googleapis.com",       # Firestore
    "identitytoolkit.googleapis.com", # Firebase Auth
    "firebase.googleapis.com",        # Firebase Management
  ])
  service            = each.key
  disable_on_destroy = false
}

# --- 3. Initialize Firebase & Firestore ---
resource "google_firebase_project" "default" {
  provider   = google-beta
  project    = var.project_id
  depends_on = [google_project_service.services]
}

resource "google_firestore_database" "database" {
  provider    = google-beta
  project     = var.project_id
  name        = "(default)" # Firebase requires the "(default)" database
  location_id = var.region
  type        = "FIRESTORE_NATIVE"
  depends_on  = [google_firebase_project.default]
}

# --- 4. Configure Firebase Auth (Identity Platform) ---
#
# TODO: Break this out so it is only applied once per project
#
# resource "google_identity_platform_config" "auth" {
#  provider = google-beta
#  project  = var.project_id
#
#  sign_in {
#    allow_duplicate_emails = false
#    email {
#      enabled           = true
#      password_required = true
#    }
#  }
#  depends_on = [google_project_service.services]
#}

# --- 5. Cloud Run Service Setup ---

# Create a dedicated Service Account for the Cloud Run instance
resource "google_service_account" "cloud_run_sa" {
  account_id   = "cloud-run-sa"
  display_name = "Cloud Run Service Account"
}

# Grant the Service Account access to Firestore
resource "google_project_iam_member" "firestore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_service
resource "google_cloud_run_v2_service" "cloud_run" {
  name     = var.name
  location = var.region

  template {
    service_account = google_service_account.cloud_run_sa.email
    containers {
      # Use a placeholder image initially
      image = "us-docker.pkg.dev/cloudrun/container/hello"
      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
    }
  }
  depends_on = [google_firestore_database.database]

  lifecycle {
    ignore_changes = [
      client,
      client_version,
      build_config,
      template[0].containers,
    ]
  }
}

# --- 6. Allow Public Access ---
resource "google_cloud_run_v2_service_iam_member" "public_access" {
  name     = google_cloud_run_v2_service.cloud_run.name
  location = google_cloud_run_v2_service.cloud_run.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# --- 7. Blocking Function & Secrets ---

# Enable additional APIs
resource "google_project_service" "additional_services" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com"
  ])
  service            = each.key
  disable_on_destroy = false
}

# Create Secret for Allowed Emails
resource "google_secret_manager_secret" "auth_allowed_emails" {
  provider  = google-beta
  project   = var.project_id
  secret_id = "auth-allowed-emails"
  replication {
    auto {}
  }
  depends_on = [google_project_service.additional_services]
}

resource "google_secret_manager_secret_version" "auth_allowed_emails_version" {
  provider    = google-beta
  secret      = google_secret_manager_secret.auth_allowed_emails.id
  secret_data = "placeholder@example.com" # Initial placeholder

  lifecycle {
    ignore_changes = [
      enabled,
      secret_data
    ]
  }
}

# Service Account for the Function
resource "google_service_account" "function_sa" {
  account_id   = "auth-blocking-function-sa"
  display_name = "Auth Blocking Function Service Account"
}

# Grant Function SA access to the Secret
resource "google_secret_manager_secret_iam_member" "function_sa_secret_access" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.auth_allowed_emails.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.function_sa.email}"
}

# Storage Bucket for Function Source
resource "google_storage_bucket" "function_bucket" {
  provider                    = google-beta
  project                     = var.project_id
  name                        = "${var.project_id}-gcf-source"
  location                    = var.region
  uniform_bucket_level_access = true
  depends_on                  = [google_project_service.additional_services]
}

# Zip the function code
data "archive_file" "function_zip" {
  type        = "zip"
  source_dir  = "../blocking_functions"
  output_path = "/tmp/blocking_functions.zip"
}

# Upload zip to bucket
resource "google_storage_bucket_object" "function_archive" {
  name   = "blocking_functions.${data.archive_file.function_zip.output_md5}.zip"
  bucket = google_storage_bucket.function_bucket.name
  source = data.archive_file.function_zip.output_path
}

# Cloud Function (Gen 2)
resource "google_cloudfunctions2_function" "blocking_function" {
  provider = google-beta
  project  = var.project_id
  name     = "auth-before-create"
  location = var.region

  build_config {
    runtime     = "nodejs24"
    entry_point = "beforeCreate" # Export name in index.js
    source {
      storage_source {
        bucket = google_storage_bucket.function_bucket.name
        object = google_storage_bucket_object.function_archive.name
      }
    }
  }

  service_config {
    max_instance_count    = 10
    available_memory      = "256M"
    timeout_seconds       = 60
    service_account_email = google_service_account.function_sa.email
    environment_variables = {
      GCLOUD_PROJECT = var.project_id
    }
  }

  depends_on = [
    google_project_service.additional_services,
    google_secret_manager_secret_iam_member.function_sa_secret_access
  ]
}

# --- 8. Outputs ---
output "project_id" {
  value = var.project_id
}

output "service_account_email" {
  value       = google_service_account.cloud_run_sa.email
  description = "The email of the service account running the application"
}

output "cloud_run_url" {
  value       = google_cloud_run_v2_service.cloud_run.uri
  description = "The publicly accessible URL of the Cloud Run service"
}

output "blocking_function_uri" {
  value = google_cloudfunctions2_function.blocking_function.service_config[0].uri
}
