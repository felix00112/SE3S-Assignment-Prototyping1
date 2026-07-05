# GCP Terraform MVP

This is the first deliberately small Terraform deployment for the booking workflow MVP.

It creates:

- one custom VPC and subnet
- firewall rules for SSH and the FastAPI port
- one Ubuntu Compute Engine VM
- Docker Compose on the VM
- Redis, the FastAPI API, and one or more worker containers

The goal is to de-risk GCP and Terraform early. This is not the final architecture with managed Redis, load balancing, or autoscaling.

## Why This Shape

The current MVP bottleneck is the worker path that drains the Redis booking queue and runs the atomic Lua reservation script. The assignment allows separate `1` / `3` / `5` deployments and only requires scaling the component with the biggest effect on the chosen metric, so this setup scales only the `worker` Compose service.

Redis and the API stay single-instance on the same VM for now. That keeps network, IAM, image registry, and service orchestration work out of the first infrastructure milestone.

## Prerequisites

- Terraform `>= 1.5`
- Google Cloud SDK authenticated with application default credentials
- a GCP project with Compute Engine API enabled
- the selected `source_ref` pushed to the configured Git repository

```bash
gcloud auth application-default login
gcloud services enable compute.googleapis.com --project YOUR_PROJECT_ID
```

## Deploy

```bash
cd infrastructure/terraform/gcp
terraform init
terraform apply \
  -var="project_id=YOUR_PROJECT_ID" \
  -var="source_ref=workflow-mvp-booking" \
  -var="worker_replicas=1"
```

Use `worker_replicas=3` or `worker_replicas=5` for the other comparison deployments.

After apply finishes, Terraform prints `api_url`.

## Smoke Test

```bash
curl "$(terraform output -raw api_url)/health"

curl -X POST "$(terraform output -raw api_url)/events/1/book" \
  -H "content-type: application/json" \
  -d '{"user_id":"user-1"}'
```

Check the reservation status with the returned `reservation_id`:

```bash
curl "$(terraform output -raw api_url)/reservations/RESERVATION_ID"
```

## Debug

SSH to the VM:

```bash
gcloud compute ssh se3s-mvp-vm --zone europe-west3-a --project YOUR_PROJECT_ID
```

Useful commands on the VM:

```bash
cd /opt/se3s/app
sudo docker-compose -f docker-compose.gcp.yml ps
sudo docker-compose -f docker-compose.gcp.yml logs -f api
sudo docker-compose -f docker-compose.gcp.yml logs -f worker
```

## Destroy

```bash
terraform destroy -var="project_id=YOUR_PROJECT_ID"
```
