{{/*
Nom complet de l'application
*/}}
{{- define "homepage.fullname" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Labels communs Kubernetes recommandés
*/}}
{{- define "homepage.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Values.customLabels }}
{{ toYaml .Values.customLabels }}
{{- end }}
{{- end -}}

{{/*
Selector labels pour les pods
*/}}
{{- define "homepage.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Nom du ServiceAccount
Retourne le nom personnalisé si défini, sinon le nom du chart, ou "default" si désactivé
*/}}
{{- define "homepage.serviceAccountName" -}}
{{- if .Values.serviceAccount.enabled -}}
{{- default (include "homepage.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
default
{{- end -}}
{{- end -}}
