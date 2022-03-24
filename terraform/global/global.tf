variable "project" {
  type = string
}
variable "location" {
  type        = string
  description = "The default App Engine region. For instance 'europe-west'"
  default     = "us-central1"
}

terraform {
  backend "gcs" {
    bucket = "terraform-state-streamstate"
    prefix = "terraform/state"
  }
}

provider "google" {
  project = var.project
  region  = var.location
}

# Use firestore
## apparently I need to enable (but not instantiate) app engine 
## to use firestore from terraform
/*resource "google_app_engine_application" "dummyapp" {
  provider      = google-beta
  location_id   = "us-central" # var.regio.1n
  project       = var.project
  database_type = "CLOUD_FIRESTORE"
}
*/
resource "google_project_service" "resource_manager" {
  project = var.project
  service = "cloudresourcemanager.googleapis.com"
}


resource "google_project_service" "dns" {
  project                    = var.project
  service                    = "dns.googleapis.com"
  disable_dependent_services = true
  depends_on                 = [google_project_service.resource_manager]
}

# enable firestore
/*resource "google_project_service" "firestore" {
  project                    = var.project
  service                    = "firestore.googleapis.com"
  disable_dependent_services = true
  depends_on = [
    google_project_service.resource_manager,
    google_app_engine_application.dummyapp
  ]
}*/



resource "google_project_service" "iam" {
  project    = var.project
  service    = "iam.googleapis.com"
  depends_on = [google_project_service.resource_manager]
}
resource "google_project_service" "artifactregistry" {
  project    = var.project
  service    = "artifactregistry.googleapis.com"
  depends_on = [google_project_service.resource_manager]
}

resource "google_project_service" "container_cluster" {
  project                    = var.project
  service                    = "container.googleapis.com"
  disable_dependent_services = true
  depends_on                 = [google_project_service.resource_manager]
}

resource "google_artifact_registry_repository" "artifactrepo" {
  provider      = google-beta
  project       = var.project
  location      = var.location
  repository_id = var.project
  description   = "global docker repo"
  format        = "DOCKER"
  depends_on    = [google_project_service.artifactregistry]
}

resource "google_compute_address" "staticgkeip" {
  name   = "streamstate-regional-ip"
  region = var.location
}

resource "google_dns_managed_zone" "streamstate-zone" {
  name        = "streamstate-zone"
  dns_name    = "streamstate.org." #example-${random_id.rnd.hex}.com."
  description = "streamstate zone"
}

resource "google_dns_record_set" "streamstate-recordset-a" {
  provider     = google-beta
  project      = var.project
  managed_zone = google_dns_managed_zone.streamstate-zone.name
  name         = "*.streamstate.org." # apparently this is the actual domain name :|
  type         = "A"
  rrdatas = [
    google_compute_address.staticgkeip.address
  ]
  ttl = 86400
  depends_on = [
    google_compute_address.staticgkeip
  ]
}

resource "google_dns_record_set" "streamstate-recordset" {
  provider     = google-beta
  project      = var.project
  managed_zone = google_dns_managed_zone.streamstate-zone.name
  name         = "*.streamstate.org." # apparently this is the actual domain name :|
  type         = "CAA"
  rrdatas      = ["0 issue \"letsencrypt.org\"", "0 issue \"pki.goog\""] # hmm, do I need this?
  ttl          = 86400
  depends_on = [
    google_compute_address.staticgkeip
  ]
}

