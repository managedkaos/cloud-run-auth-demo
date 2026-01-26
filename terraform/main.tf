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
# Once per project
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
}

# --- 6. Allow Public Access ---
resource "google_cloud_run_v2_service_iam_member" "public_access" {
  name     = google_cloud_run_v2_service.cloud_run.name
  location = google_cloud_run_v2_service.cloud_run.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# --- 7. Outputs ---
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
