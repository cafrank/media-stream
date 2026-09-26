{{/* Chart name */}}
{{- define "record-pool.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Fully qualified app name */}}
{{- define "record-pool.fullname" -}}
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

{{- define "record-pool.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "record-pool.labels" -}}
helm.sh/chart: {{ include "record-pool.chart" . }}
{{ include "record-pool.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "record-pool.selectorLabels" -}}
app.kubernetes.io/name: {{ include "record-pool.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: web
{{- end }}

{{- define "record-pool.image" -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default .Chart.AppVersion) }}
{{- end }}

{{/* affinity, or podAntiAffinity soft/hard over this release's pods */}}
{{- define "record-pool.affinity" -}}
{{- if .Values.affinity }}
{{- toYaml .Values.affinity }}
{{- else if eq .Values.podAntiAffinity "soft" }}
podAntiAffinity:
  preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        topologyKey: kubernetes.io/hostname
        labelSelector:
          matchLabels:
            {{- include "record-pool.selectorLabels" . | nindent 12 }}
{{- else if eq .Values.podAntiAffinity "hard" }}
podAntiAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
    - topologyKey: kubernetes.io/hostname
      labelSelector:
        matchLabels:
          {{- include "record-pool.selectorLabels" . | nindent 10 }}
{{- end }}
{{- end }}

{{- define "record-pool.validate" -}}
{{- if not (has .Values.podAntiAffinity (list "" "soft" "hard")) }}
{{- fail (printf "podAntiAffinity must be \"\", \"soft\" or \"hard\" (got %q)" .Values.podAntiAffinity) }}
{{- end }}
{{- end }}
