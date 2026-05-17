{{- define "task-api.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "task-api.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- include "task-api.name" . -}}
{{- end -}}
{{- end -}}

{{- define "task-api.labels" -}}
app: {{ include "task-api.fullname" . }}
managed-by: {{ .Values.labels.managedBy | quote }}
app.kubernetes.io/name: {{ include "task-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
{{- end -}}

{{- define "task-api.selectorLabels" -}}
app: {{ include "task-api.fullname" . }}
app.kubernetes.io/name: {{ include "task-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "task-api.databaseUrl" -}}
{{- printf "postgres://%s:%s@%s:%s/%s?options=-csearch_path%%3D%s&sslmode=%s" .Values.config.dbUser .Values.secret.dbPassword .Values.config.dbHost .Values.config.dbPort .Values.config.dbName .Values.config.dbSchema .Values.config.dbSsl -}}
{{- end -}}
