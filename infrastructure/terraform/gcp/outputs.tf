output "api_url" {
  description = "Public URL for the FastAPI MVP."
  value       = "http://${google_compute_instance.mvp.network_interface[0].access_config[0].nat_ip}:8000"
}

output "instance_name" {
  description = "Compute Engine instance name."
  value       = google_compute_instance.mvp.name
}

output "ssh_command" {
  description = "Useful SSH command for checking Docker Compose logs."
  value       = "gcloud compute ssh ${google_compute_instance.mvp.name} --zone ${var.zone} --project ${var.project_id}"
}
