# Scalability Experiment Checklist (minimum + vertical bonus)

Tight, run-it-top-to-bottom protocol for the graded scaling result (req 2 a/b/c) plus
the vertical-scaling bonus (2d). One test, one metric, six runs.

## 0. One-time prep
- [ ] Branch pushed to GitHub (VMs clone `source_ref` at boot; local changes don't count).
- [ ] `gcloud auth application-default login` done, project set, Compute API enabled.
- [ ] `terraform` and `gcloud` on PATH.
- [ ] Set your project once:
  ```bash
  export PROJECT=your-project-id
  ```

## 1. Constants (hold these fixed so runs are comparable)
- Test: `constant_load` (unique user per request → pure throughput)
- Load: `K6_VUS=600`, `K6_DURATION=1m`  (600 VUs is enough to saturate up to 5 nodes)
- Seats: default `1000000` (won't sell out during the run)
- Machines: `e2-medium` (baseline) and `e2-standard-4` (vertical bonus)

> Keep VUs identical across every run. The comparison is "same offered load, more/bigger
> resources → higher throughput."

## 2. Run all six (baseline a/b/c + bonus a/b/c)
Each config is deploy → test (waits for the LB, fetches reports, prints metrics) → destroy:

```bash
for M in e2-medium e2-standard-4; do
  for N in 1 3 5; do
    scripts/gcp/deploy.sh   -p "$PROJECT" -n "$N" -m "$M"
    K6_VUS=600 K6_DURATION=1m \
      scripts/gcp/run-tests.sh -p "$PROJECT" -o "results/$M-${N}nodes" constant_load
    scripts/gcp/destroy.sh  -p "$PROJECT"
  done
done
```

If you'd rather run cells one at a time (safer — a failed deploy won't break the loop),
run the three commands per row of the table below, changing `-n` and `-m`.

## 3. Record the numbers
`run-tests.sh` prints a summary after each run. Record these four per run
(throughput is already per-second; accepted/s = `Accepted` ÷ 60):

| Machine | Nodes | Throughput (req/s) | Accepted (count → ÷60 = /s) | 503 shed (count) | Latency p95 (ms) |
|---------|-------|--------------------|-----------------------------|------------------|------------------|
| e2-medium    | 1 |  |  |  |  |
| e2-medium    | 3 |  |  |  |  |
| e2-medium    | 5 |  |  |  |  |
| e2-standard-4 | 1 |  |  |  |  |
| e2-standard-4 | 3 |  |  |  |  |
| e2-standard-4 | 5 |  |  |  |  |

Raw CSV + summary JSON for each run are saved under `results/<machine>-<N>nodes/k6-out/`.

## 4. What each column is for (the slides)
- **Throughput (req/s)** = the required scaling metric. Plot vs nodes: it should **rise
  1→3→5** (horizontal scaling of the stateless API tier works).
- **Accepted/s** = booking throughput, gated by the single worker → stays roughly **flat**
  across nodes at a fixed machine. This is your **limitations** slide ("the single worker
  is the ceiling"). It **rises** with the bigger machine (worker gets more CPU) → that's
  the **vertical-scaling** result (bonus 2d).
- **503 shed** = the admission gate protecting the worker under overload → evidence for
  req 3 (can't overload a downstream component). No extra test needed.
- **Latency p95** = optional second line; note where it spikes (saturation).

Two lines carry the whole story:
1. Throughput vs nodes (per machine) → horizontal scaling.
2. Accepted/s: e2-medium vs e2-standard-4 → vertical scaling + the worker limit.

## 5. Cost
Six short-lived deployments on the $50 grant is a few dollars at most — as long as every
run ends with `destroy.sh`. If you abort mid-loop, run `scripts/gcp/destroy.sh -p "$PROJECT"`
manually before leaving.
