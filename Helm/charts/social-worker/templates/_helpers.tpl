{{- define "social-worker.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "social-worker.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- include "social-worker.name" . -}}
{{- end -}}
{{- end -}}

{{- define "social-worker.labels" -}}
app: {{ include "social-worker.fullname" . }}
managed-by: {{ .Values.labels.managedBy | quote }}
app.kubernetes.io/name: {{ include "social-worker.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
{{- end -}}

{{- define "social-worker.selectorLabels" -}}
app: {{ include "social-worker.fullname" . }}
app.kubernetes.io/name: {{ include "social-worker.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "social-worker.databaseUrl" -}}
{{- printf "postgres://%s:%s@%s:%s/%s?options=-csearch_path%%3D%s&sslmode=%s" .Values.config.dbUser .Values.secret.dbPassword .Values.config.dbHost .Values.config.dbPort .Values.config.dbName .Values.config.dbSchema .Values.config.dbSsl -}}
{{- end -}}
