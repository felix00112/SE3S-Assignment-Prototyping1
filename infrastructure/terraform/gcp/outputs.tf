output "api_url" {
  description = "Public URL for the FastAPI MVP."
  value       = "http://${google_compute_instance.mvp[0].network_interface[0].access_config[0].nat_ip}:8000"
}

output "coordinator_instance_name" {
  description = "Compute Engine instance name for the API and Redis coordinator node."
  value       = google_compute_instance.mvp[0].name
}

output "ssh_command" {
  description = "Useful SSH command for checking Docker Compose logs on the coordinator node."
  value       = "gcloud compute ssh ${google_compute_instance.mvp[0].name} --zone ${var.zone} --project ${var.project_id}"
}

output "node_names" {
  description = "All Compute Engine instance names in the MVP deployment."
  value       = [for instance in google_compute_instance.mvp : instance.name]
}

output "worker_ssh_commands" {
  description = "SSH commands for worker nodes."
  value = [
    for instance in slice(google_compute_instance.mvp, 1, length(google_compute_instance.mvp)) :
    "gcloud compute ssh ${instance.name} --zone ${var.zone} --project ${var.project_id}"
  ]
}

output "load_generator_instance_name" {
  description = "Compute Engine instance name for the optional k6 load-generator VM."
  value       = var.load_generator_enabled ? google_compute_instance.load_generator[0].name : null
}

output "load_generator_ssh_command" {
  description = "SSH command for the optional k6 load-generator VM."
  value       = var.load_generator_enabled ? "gcloud compute ssh ${google_compute_instance.load_generator[0].name} --zone ${var.zone} --project ${var.project_id}" : null
}
