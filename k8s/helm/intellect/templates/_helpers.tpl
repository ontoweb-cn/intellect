{{/*
Expand the name of the chart.
*/}}
{{- define "intellect.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "intellect.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "intellect.labels" -}}
helm.sh/chart: {{ include "intellect.name" . }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "intellect.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Agent image
*/}}
{{- define "intellect.agentImage" -}}
{{ .Values.imageRegistry }}/intellect-agent:{{ .Values.imageTag }}
{{- end }}

{{/*
WebUI image
*/}}
{{- define "intellect.webuiImage" -}}
{{ .Values.imageRegistry }}/intellect-webui:{{ .Values.imageTag }}
{{- end }}

{{/*
Persistence name
*/}}
{{- define "intellect.persistenceName" -}}
{{ include "intellect.fullname" . }}-data
{{- end }}
