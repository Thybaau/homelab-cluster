{{/*
Nom complet de l'application
*/}}
{{- define "jarod-rbac.fullname" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Labels communs Kubernetes recommandés
*/}}
{{- define "jarod-rbac.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels pour les pods
*/}}
{{- define "jarod-rbac.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Nom du ServiceAccount
Retourne le nom personnalisé si défini, sinon le nom du chart, ou "default" si désactivé
*/}}
{{- define "jarod-rbac.serviceAccountName" -}}
{{- if .Values.serviceAccount.enabled -}}
{{- default (include "jarod-rbac.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
default
{{- end -}}
{{- end -}}
