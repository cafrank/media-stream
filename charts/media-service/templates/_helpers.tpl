{{/* Chart name */}}
{{- define "media-service.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Fully qualified app name */}}
{{- define "media-service.fullname" -}}
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

{{- define "media-service.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "media-service.labels" -}}
helm.sh/chart: {{ include "media-service.chart" . }}
{{ include "media-service.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "media-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "media-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: app
{{- end }}

{{- define "media-service.serviceName" -}}
{{- default (include "media-service.fullname" .) .Values.service.name }}
{{- end }}

{{- define "media-service.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "media-service.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "media-service.image" -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default .Chart.AppVersion) }}
{{- end }}

{{/* ---- MongoDB ---- */}}

{{- define "media-service.mongodb.fullname" -}}
{{- printf "%s-mongodb" (include "media-service.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "media-service.mongodb.selectorLabels" -}}
app.kubernetes.io/name: {{ include "media-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: mongodb
{{- end }}

{{/* Secret holding MONGO_INITDB_ROOT_USERNAME / _PASSWORD */}}
{{- define "media-service.mongodb.authSecretName" -}}
{{- printf "%s-auth" (include "media-service.mongodb.fullname" .) }}
{{- end }}

{{/* Secret + key the app reads SPRING_DATA_MONGODB_URI from */}}
{{- define "media-service.mongoUriSecretName" -}}
{{- if and (not .Values.mongodb.enabled) .Values.externalMongodb.existingSecret }}
{{- .Values.externalMongodb.existingSecret }}
{{- else }}
{{- printf "%s-mongodb-uri" (include "media-service.fullname" .) }}
{{- end }}
{{- end }}

{{- define "media-service.mongoUriSecretKey" -}}
{{- if and (not .Values.mongodb.enabled) .Values.externalMongodb.existingSecret }}
{{- .Values.externalMongodb.existingSecretKey }}
{{- else -}}
SPRING_DATA_MONGODB_URI
{{- end }}
{{- end }}

{{/* True when the chart must render the URI Secret itself */}}
{{- define "media-service.createMongoUriSecret" -}}
{{- if or .Values.mongodb.enabled (not .Values.externalMongodb.existingSecret) }}true{{ end }}
{{- end }}

{{- define "media-service.validate" -}}
{{- if and (not .Values.mongodb.enabled) (not .Values.externalMongodb.uri) (not .Values.externalMongodb.existingSecret) }}
{{- fail "mongodb.enabled=false requires externalMongodb.uri or externalMongodb.existingSecret" }}
{{- end }}
{{- if and .Values.mongodb.enabled .Values.mongodb.auth.enabled (not .Values.mongodb.auth.rootPassword) }}
{{- fail "mongodb.auth.enabled=true requires mongodb.auth.rootPassword" }}
{{- end }}
{{- end }}
