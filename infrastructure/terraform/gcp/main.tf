provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

locals {
  subnet_cidr      = "10.20.0.0/24"
  redis_private_ip = cidrhost(local.subnet_cidr, 10)

  # Every node (index 0..N-1) serves an API on :8000 at a deterministic private IP.
  # The load balancer on node 0 fans out across all of them.
  api_backend_ips = [for i in range(var.node_count) : cidrhost(local.subnet_cidr, 10 + i)]
  nginx_upstream  = join("\n", [for ip in local.api_backend_ips : "        server ${ip}:8000;"])

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

resource "google_compute_firewall" "lb" {
  name    = "${var.name_prefix}-allow-lb"
  network = google_compute_network.mvp.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = var.api_source_ranges
  target_tags   = ["${var.name_prefix}-lb"]
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
  name         = count.index == 0 ? "${var.name_prefix}-vm" : "${var.name_prefix}-api-${count.index + 1}"
  machine_type = var.machine_type
  # Every node serves the API (so it needs the -api tag). Node 0 additionally
  # hosts the single Redis + worker (-redis) and the Nginx load balancer (-lb).
  tags = concat(
    ["${var.name_prefix}-ssh", "${var.name_prefix}-api"],
    count.index == 0 ? ["${var.name_prefix}-redis", "${var.name_prefix}-lb"] : []
  )
  labels = merge(local.labels, {
    role = count.index == 0 ? "coordinator" : "api"
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
    source_repo_url             = var.source_repo_url
    source_ref                  = var.source_ref
    node_role                   = count.index == 0 ? "coordinator" : "api"
    redis_host                  = local.redis_private_ip
    worker_replicas_per_node    = var.worker_replicas_per_node
    worker_batch_size           = var.worker_batch_size
    worker_interval_seconds     = var.worker_interval_seconds
    worker_synthetic_dummy_mode = var.worker_synthetic_dummy_mode
    event_id                    = var.event_id
    initial_seats               = var.initial_seats
    # Load balancer config: only the coordinator (node 0) uses these.
    nginx_upstream  = count.index == 0 ? local.nginx_upstream : ""
    api_backend_ips = count.index == 0 ? join(" ", local.api_backend_ips) : ""
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
    source_repo_url             = var.source_repo_url
    source_ref                  = var.source_ref
    node_role                   = "load-generator"
    redis_host                  = local.redis_private_ip
    worker_replicas_per_node    = var.worker_replicas_per_node
    worker_batch_size           = var.worker_batch_size
    worker_interval_seconds     = var.worker_interval_seconds
    worker_synthetic_dummy_mode = var.worker_synthetic_dummy_mode
    event_id                    = var.event_id
    initial_seats               = var.initial_seats
    nginx_upstream              = ""
    api_backend_ips             = ""
  })
}
