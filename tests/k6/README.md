# k6 Tests

This folder contains the primary load and stress test scenarios for the booking flow.

## Basic Test Set-Up

+ Start docker compose

```bash
docker compose up --build
```

+ Start the test

```bash
docker compose run --rm k6 run {test-name.js}
```

## Running in the cloud

+ Once the service has up and running check the external IP and change it in the `k6_config.yaml`
+ Define which test you want to run in `k6-job.yaml`
```bash
kubectl apply -f k6-config.yaml
kubectl apply -f k6-job.yaml
kubectl logs job/k6-booking-test
```