provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

locals {
  labels = {
    app         = "se3s"
    component   = "booking-mvp"
    environment = "prototype"
  }
}

resource "google_compute_network" "mvp" {
  name                    = "${var.name_prefix}-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "mvp" {
  name          = "${var.name_prefix}-subnet"
  ip_cidr_range = "10.20.0.0/24"
  network       = google_compute_network.mvp.id
  region        = var.region
}

resource "google_compute_firewall" "api" {
  name    = "${var.name_prefix}-allow-api"
  network = google_compute_network.mvp.name

  allow {
    protocol = "tcp"
    ports    = ["8000"]
  }

  source_ranges = var.api_source_ranges
  target_tags   = ["${var.name_prefix}-api"]
}

resource "google_compute_firewall" "ssh" {
  name    = "${var.name_prefix}-allow-ssh"
  network = google_compute_network.mvp.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.ssh_source_ranges
  target_tags   = ["${var.name_prefix}-ssh"]
}

resource "google_compute_instance" "mvp" {
  name         = "${var.name_prefix}-vm"
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["${var.name_prefix}-api", "${var.name_prefix}-ssh"]
  labels       = local.labels

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = var.boot_disk_size_gb
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.mvp.id

    access_config {
      # Ephemeral public IP for a short-lived assignment prototype.
    }
  }

  metadata_startup_script = templatefile("${path.module}/templates/startup.sh.tftpl", {
    source_repo_url = var.source_repo_url
    source_ref      = var.source_ref
    worker_replicas = var.worker_replicas
    event_id        = var.event_id
    initial_seats   = var.initial_seats
  })
}
