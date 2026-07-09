provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

locals {
  subnet_cidr      = "10.20.0.0/24"
  redis_private_ip = cidrhost(local.subnet_cidr, 10)

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
  ip_cidr_range = local.subnet_cidr
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

resource "google_compute_firewall" "internal" {
  name    = "${var.name_prefix}-allow-internal"
  network = google_compute_network.mvp.name

  allow {
    protocol = "tcp"
    ports    = ["6379"]
  }

  source_ranges = [local.subnet_cidr]
  target_tags   = ["${var.name_prefix}-redis"]
}

resource "google_compute_instance" "mvp" {
  count        = var.node_count
  name         = count.index == 0 ? "${var.name_prefix}-vm" : "${var.name_prefix}-node-${count.index + 1}"
  machine_type = var.machine_type
  zone         = var.zone
  tags = concat(
    ["${var.name_prefix}-ssh"],
    count.index == 0 ? ["${var.name_prefix}-api", "${var.name_prefix}-redis"] : []
  )
  labels = merge(local.labels, {
    role = count.index == 0 ? "coordinator" : "worker"
  })

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = var.boot_disk_size_gb
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.mvp.id
    network_ip = cidrhost(local.subnet_cidr, 10 + count.index)

    access_config {
      # Ephemeral public IP for a short-lived assignment prototype.
    }
  }

  metadata_startup_script = templatefile("${path.module}/templates/startup.sh.tftpl", {
    source_repo_url          = var.source_repo_url
    source_ref               = var.source_ref
    node_role                = count.index == 0 ? "coordinator" : "worker"
    redis_host               = local.redis_private_ip
    worker_replicas_per_node = var.worker_replicas_per_node
    event_id                 = var.event_id
    initial_seats            = var.initial_seats
  })
}

resource "google_compute_instance" "load_generator" {
  count        = var.load_generator_enabled ? 1 : 0
  name         = "${var.name_prefix}-loadgen"
  machine_type = var.load_generator_machine_type
  zone         = var.zone
  tags         = ["${var.name_prefix}-ssh"]
  labels = merge(local.labels, {
    role = "load-generator"
  })

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = var.boot_disk_size_gb
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.mvp.id
    network_ip = cidrhost(local.subnet_cidr, 20)

    access_config {
      # Ephemeral public IP for a short-lived assignment prototype.
    }
  }

  metadata_startup_script = templatefile("${path.module}/templates/startup.sh.tftpl", {
    source_repo_url          = var.source_repo_url
    source_ref               = var.source_ref
    node_role                = "load-generator"
    redis_host               = local.redis_private_ip
    worker_replicas_per_node = var.worker_replicas_per_node
    event_id                 = var.event_id
    initial_seats            = var.initial_seats
  })
}
