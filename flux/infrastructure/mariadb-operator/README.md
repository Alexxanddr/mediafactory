# MariaDB operator monitoring

The operator exposes Prometheus metrics on port 8080. With ServiceMonitor disabled,
chart 26.10.2 does not create a metrics Service. `service.yaml` provides the stable
internal endpoint used by Uptime Kuma without requiring Prometheus CRDs.

The monitor checks `/metrics` and requires HTTP 200. Its Service selector targets
only the main operator, excluding the webhook and certificate controller. This
checks the operator metrics endpoint, not MariaDB query availability.

The 2026-10-30 correction replaces a nonexistent Service target and a root-path
404 expectation. Flux owns both the Service and HelmRelease annotation changes;
the Kuma operator updates the existing monitor in place, preserving its ID.
