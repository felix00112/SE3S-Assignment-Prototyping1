#!/usr/bin/env python3
"""Print headline metrics from a k6 --summary-export JSON file.

Usage: summarize.py <summary.json>

The full time series for plots lives in the companion raw-*.csv (k6 --out csv);
this only pretty-prints the end-of-run aggregates so you get instant feedback.
"""
import json
import sys


def get(metrics, name, *keys, default="-"):
    m = metrics.get(name)
    if not isinstance(m, dict):
        return default
    # --summary-export nests actual numbers either directly or under "values".
    values = m.get("values", m)
    for k in keys:
        if k in values:
            return values[k]
    return default


def main():
    if len(sys.argv) < 2:
        print("usage: summarize.py <summary.json>", file=sys.stderr)
        return 1

    with open(sys.argv[1]) as f:
        data = json.load(f)
    metrics = data.get("metrics", data)

    def num(v):
        return f"{v:.2f}" if isinstance(v, (int, float)) else str(v)

    rows = [
        ("Requests (total)", num(get(metrics, "http_reqs", "count"))),
        ("Throughput (req/s)", num(get(metrics, "http_reqs", "rate"))),
        ("Iterations (bookings)", num(get(metrics, "iterations", "count"))),
        ("Max concurrent users (VUs)", num(get(metrics, "vus_max", "value", "max"))),
        ("Latency avg (ms)", num(get(metrics, "http_req_duration", "avg"))),
        ("Latency p95 (ms)", num(get(metrics, "http_req_duration", "p(95)"))),
        ("Latency max (ms)", num(get(metrics, "http_req_duration", "max"))),
        ("Accepted (200/201)", num(get(metrics, "accepted", "count", default=0))),
        ("Rejected - rate limiter (429)", num(get(metrics, "rejected_rate_limited", "count", default=0))),
        ("Rejected - admission gate (503)", num(get(metrics, "rejected_admission", "count", default=0))),
        ("Other status", num(get(metrics, "other_status", "count", default=0))),
    ]
    width = max(len(label) for label, _ in rows)
    for label, value in rows:
        print(f"   {label.ljust(width)} : {value}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
