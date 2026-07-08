# GCP Terraform MVP

This is the first deliberately small Terraform deployment for the booking workflow MVP.

It creates:

- one custom VPC and subnet
- firewall rules for SSH and the FastAPI port
- `1`, `3`, or `5` Ubuntu Compute Engine VMs using the same machine type
- Docker Compose on every VM
- Redis and the FastAPI API on the coordinator node
- worker containers on every node

The goal is to keep the assignment deployment reproducible without jumping straight to managed Redis, load balancing, Kubernetes, or autoscaling.

## Why This Shape

The current MVP bottleneck is the worker path that drains the Redis booking queue and runs the atomic Lua reservation script. The assignment asks for `1` / `3` / `5` node configurations, so this setup scales the number of VM nodes while keeping the public API on one coordinator node.

The coordinator node runs Redis, the API, and one worker. Additional nodes run worker containers that connect to Redis over the private VPC IP. The Redis port is only opened to the deployment subnet by the Terraform firewall rule. This keeps the experiment focused on worker-side queue draining without requiring a load balancer yet.

Node layout:

```text
1 node:
  se3s-mvp-vm: API + Redis + worker

3 nodes:
  se3s-mvp-vm: API + Redis + worker
  se3s-mvp-node-2: worker
  se3s-mvp-node-3: worker

5 nodes:
  se3s-mvp-vm: API + Redis + worker
  se3s-mvp-node-2: worker
  se3s-mvp-node-3: worker
  se3s-mvp-node-4: worker
  se3s-mvp-node-5: worker
```

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
  -var="source_ref=gcp-terraform-mvp" \
  -var="node_count=1"
```

Use `node_count=3` or `node_count=5` for the other comparison deployments.

If you deployed the older single-VM Terraform version first, destroy it before applying this node-count version. That avoids Terraform replacing the original VM while you are still debugging:

```bash
terraform destroy -var="project_id=YOUR_PROJECT_ID"
```

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

Worker nodes use `docker-compose.gcp-worker.yml`:

```bash
cd /opt/se3s/app
sudo docker-compose -f docker-compose.gcp-worker.yml ps
sudo docker-compose -f docker-compose.gcp-worker.yml logs -f worker
```

## Destroy

```bash
terraform destroy -var="project_id=YOUR_PROJECT_ID"
```
