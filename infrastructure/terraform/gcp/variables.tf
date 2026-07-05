variable "project_id" {
  description = "GCP project ID that will host the MVP deployment."
  type        = string
}

variable "region" {
  description = "GCP region for the VPC subnet."
  type        = string
  default     = "europe-west3"
}

variable "zone" {
  description = "GCP zone for the Compute Engine VM."
  type        = string
  default     = "europe-west3-a"
}

variable "name_prefix" {
  description = "Prefix used for GCP resource names."
  type        = string
  default     = "se3s-mvp"
}

variable "machine_type" {
  description = "Compute Engine machine type for the single-node MVP deployment."
  type        = string
  default     = "e2-medium"
}

variable "boot_disk_size_gb" {
  description = "Boot disk size for Docker images, containers, and Redis data."
  type        = number
  default     = 20
}

variable "source_repo_url" {
  description = "Git repository URL cloned by the VM startup script."
  type        = string
  default     = "https://github.com/felix00112/SE3S-Assignment-Prototyping1.git"
}

variable "source_ref" {
  description = "Git branch, tag, or commit checked out by the VM startup script."
  type        = string
  default     = "main"
}

variable "worker_replicas" {
  description = "Number of worker containers started with Docker Compose. Use 1, 3, or 5 for assignment comparison runs."
  type        = number
  default     = 1

  validation {
    condition     = contains([1, 3, 5], var.worker_replicas)
    error_message = "worker_replicas should be one of 1, 3, or 5 for the planned experiment matrix."
  }
}

variable "event_id" {
  description = "Prototype event ID consumed by the worker."
  type        = number
  default     = 1
}

variable "initial_seats" {
  description = "Initial Redis seat counter seeded by the startup script."
  type        = number
  default     = 100
}

variable "api_source_ranges" {
  description = "CIDR ranges allowed to reach the public API port."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ssh_source_ranges" {
  description = "CIDR ranges allowed to SSH to the VM."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
