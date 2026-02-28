{{/*
Nom complet de l'application
*/}}
{{- define "valhafin.fullname" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Labels communs
*/}}
{{- define "valhafin.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels
*/}}
{{- define "valhafin.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Backend labels
*/}}
{{- define "valhafin.backend.labels" -}}
{{ include "valhafin.labels" . }}
app.kubernetes.io/component: backend
{{- end -}}

{{/*
Frontend labels
*/}}
{{- define "valhafin.frontend.labels" -}}
{{ include "valhafin.labels" . }}
app.kubernetes.io/component: frontend
{{- end -}}

{{/*
Database labels
*/}}
{{- define "valhafin.database.labels" -}}
{{ include "valhafin.labels" . }}
app.kubernetes.io/component: database
{{- end -}}

{{/*
DATABASE_URL construction
*/}}
{{- define "valhafin.databaseUrl" -}}
postgresql://$(POSTGRES_USER):$(POSTGRES_PASSWORD)@{{ include "valhafin.fullname" . }}-database:5432/$(POSTGRES_DB)?sslmode=disable
{{- end -}}
