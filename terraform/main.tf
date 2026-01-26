variable "project_id" {
  type        = string
  description = "The GCP Project ID (must be globally unique)"
}
# --- 1. Provider & Version Setup ---
terraform {
  backend "gcs" {
    bucket = "cloud-run-and-firebase-tfstate"
    prefix = "terraform/state"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = "us-central1"
}

provider "google-beta" {
  project               = var.project_id
  region                = "us-central1"
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
  location_id = "us-central1"
  type        = "FIRESTORE_NATIVE"
  depends_on  = [google_firebase_project.default]
}

# --- 4. Configure Firebase Auth (Identity Platform) ---
resource "google_identity_platform_config" "auth" {
  provider = google-beta
  project  = var.project_id

  sign_in {
    allow_duplicate_emails = false
    email {
      enabled           = true
      password_required = true
    }
  }
  depends_on = [google_project_service.services]
}

# --- 5. Cloud Run Service Setup ---

# Create a dedicated Service Account for the Cloud Run instance
resource "google_service_account" "cloud_run_sa" {
  account_id   = "cloud-run-backend-sa"
  display_name = "Cloud Run Backend Service Account"
}

# Grant the Service Account access to Firestore
resource "google_project_iam_member" "firestore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

resource "google_cloud_run_v2_service" "backend" {
  name     = "my-app-backend"
  location = "us-central1"

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
  name     = google_cloud_run_v2_service.backend.name
  location = google_cloud_run_v2_service.backend.location
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
  value       = google_cloud_run_v2_service.backend.uri
  description = "The publicly accessible URL of the Cloud Run service"
}
