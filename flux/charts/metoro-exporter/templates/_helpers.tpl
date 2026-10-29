{{/*
Expand the name of the chart.
*/}}
{{- define "metoro.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "metoro.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "metoro.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "metoro.labels" -}}
helm.sh/chart: {{ include "metoro.chart" . }}
{{ include "metoro.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "metoro.selectorLabels" -}}
app.kubernetes.io/name: {{ include "metoro.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "metoro.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "metoro.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}


{{/*
Common non-selector labels for ServiceMonitor scraping resources.
*/}}
{{- define "metoro.serviceMonitorScraping.commonLabels" -}}
helm.sh/chart: {{ include "metoro.chart" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Create the name of the ServiceMonitor scraping collector.
*/}}
{{- define "metoro.serviceMonitorScraping.collectorName" -}}
{{- printf "%s-sm-scraper" (include "metoro.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create the name of the ServiceMonitor scraping collector config map.
*/}}
{{- define "metoro.serviceMonitorScraping.collectorConfigMapName" -}}
{{- printf "%s-config" (include "metoro.serviceMonitorScraping.collectorName" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create the name of the ServiceMonitor scraping collector headless service.
*/}}
{{- define "metoro.serviceMonitorScraping.collectorHeadlessServiceName" -}}
{{- printf "%s-headless" (include "metoro.serviceMonitorScraping.collectorName" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create the service account name used by the ServiceMonitor scraping collector.
*/}}
{{- define "metoro.serviceMonitorScraping.collectorServiceAccountName" -}}
{{- printf "%s-collector" (include "metoro.serviceMonitorScraping.collectorName" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create selector labels used by the ServiceMonitor scraping collector.
*/}}
{{- define "metoro.serviceMonitorScraping.collectorSelectorLabels" -}}
app.kubernetes.io/name: {{ include "metoro.serviceMonitorScraping.collectorName" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: service-monitor-scraper
{{- end }}

{{/*
Create the name used by the Target Allocator resources.
*/}}
{{- define "metoro.serviceMonitorScraping.targetAllocatorName" -}}
{{- $suffix := "-targetallocator" -}}
{{- $prefixLength := int (sub 63 (len $suffix)) -}}
{{- printf "%s%s" ((include "metoro.serviceMonitorScraping.collectorName" .) | trunc $prefixLength | trimSuffix "-") $suffix | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create the service account name used by the Target Allocator.
*/}}
{{- define "metoro.serviceMonitorScraping.serviceAccountName" -}}
{{- include "metoro.serviceMonitorScraping.targetAllocatorName" . }}
{{- end }}

{{/*
Create selector labels used by the Target Allocator.
*/}}
{{- define "metoro.serviceMonitorScraping.targetAllocatorSelectorLabels" -}}
app.kubernetes.io/name: {{ include "metoro.serviceMonitorScraping.targetAllocatorName" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: opentelemetry-targetallocator
{{- end }}

{{/*
Render a Kubernetes LabelSelector for the Target Allocator config. The pinned
Target Allocator version unmarshals LabelSelector fields using lower-case YAML
field names.
*/}}
{{- define "metoro.serviceMonitorScraping.targetAllocatorLabelSelector" -}}
{{- $selector := . | default dict -}}
{{- $matchLabels := get $selector "matchLabels" | default (get $selector "matchlabels") -}}
{{- $matchExpressions := get $selector "matchExpressions" | default (get $selector "matchexpressions") -}}
{{- if or $matchLabels $matchExpressions -}}
{{- with $matchLabels }}
matchlabels:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $matchExpressions }}
matchexpressions:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- else -}}
{}
{{- end -}}
{{- end }}

{{/*
Render a templated CRD when it is missing or already owned by this Helm release.
This lets upgrades install newly introduced Metoro CRDs without failing on CRDs
that are already owned by another release.
*/}}
{{- define "metoro.shouldRenderCRD" -}}
{{- $root := .root -}}
{{- $name := .name -}}
{{- $existing := lookup "apiextensions.k8s.io/v1" "CustomResourceDefinition" "" $name -}}
{{- if not $existing -}}
true
{{- else -}}
{{- $annotations := $existing.metadata.annotations | default dict -}}
{{- if and (eq (get $annotations "meta.helm.sh/release-name") $root.Release.Name) (eq (get $annotations "meta.helm.sh/release-namespace") $root.Release.Namespace) -}}
true
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Changing the set of CRD-backed informer resources, or a watched CRD's schema,
must roll existing exporter pods so MetadataWatcher.Init runs again after CRDs
are installed or upgraded. schemaRevision covers schema-only changes (an old
pod watching through a pruned schema would silently drop new fields).
*/}}
{{- define "metoro.exporter.crdWatcherChecksum" -}}
{{- toJson (dict "apiGroup" "observability.metoro.io" "version" "v1alpha1" "resources" (list "metoroalerts" "metorodashboards" "metorowebhooks" "metoroclusteringestionrules") "schemaRevision" "3") -}}
{{- end }}
