# Metoro exporter Helm chart

Vendored from https://github.com/metoro-io/metoro-helm-charts/releases/download/metoro-exporter-0.478.0/metoro-exporter-0.478.0.tgz (chart version 0.478.0).

Local patch: removed the duplicate `app.kubernetes.io/name` entry in `templates/exporter_deployment.yaml`; the chart helper already supplies this selector label. This is required because Flux rejects YAML mappings with duplicate keys during Helm post-rendering. Keep the chart otherwise aligned with upstream.
