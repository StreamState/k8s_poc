provider "google" {
  project = var.project
  region  = var.region
}

# this is the default cluster service account, this shouldn't be used for much
# we should create custom service accounts with minimal permissions
resource "google_service_account" "cluster" {
  project      = var.project
  account_id   = "service-account-id-${var.organization}"
  display_name = "Service Account ${var.organization}"
}

# this should be at the global level, multitenant
resource "google_container_cluster" "primary" {
  project  = var.project
  name     = "streamstatecluster-${var.organization}"
  location = var.region
  release_channel {
    channel = "RAPID" # "REGULAR"  
  }
  # VPC-native
  network    = "default"
  subnetwork = "default"
  ip_allocation_policy {
    cluster_ipv4_cidr_block  = "/16"
    services_ipv4_cidr_block = "/22"
  }
  #enable_autopilot = true
  workload_identity_config {
    workload_pool = "${var.project}.svc.id.goog"
  }
  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1
}

# this should be at the organization level (each organization gets their own cluster)
resource "google_container_node_pool" "primary_preemptible_nodes" {
  project    = var.project
  name       = "${var.project}pool-${var.organization}"
  location   = var.region
  version    = google_container_cluster.primary.master_version
  cluster    = google_container_cluster.primary.name
  node_count = 1 # it keeps giving me 3 nodes though
   node_config {
    preemptible  = true
    machine_type = "e2-standard-2" #"e2-medium" 
    # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    service_account = google_service_account.cluster.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }
}


data "google_container_cluster" "primary" {
  name     = google_container_cluster.primary.name
  location = var.region
}
resource "google_artifact_registry_repository_iam_member" "read" {
  provider   = google-beta
  project    = var.project
  location   = "us-central1"
  repository = var.project # see ../../global/global.tf
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.cluster.email}"
}



