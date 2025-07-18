{{- define "cluster.name" -}}
    {{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "remotemachinetemplate.controlplane.name" -}}
    {{- include "cluster.name" . }}-cp-mt
{{- end }}

{{- define "remotemachinetemplate.worker.name" -}}
    {{- include "cluster.name" . }}-worker-mt
{{- end }}

{{- define "k0scontrolplane.name" -}}
    {{- include "cluster.name" . }}-cp
{{- end }}

{{- define "k0sworkerconfigtemplate.name" -}}
    {{- include "cluster.name" . }}-machine-config
{{- end }}

{{- define "machinedeployment.name" -}}
    {{- include "cluster.name" . }}-md
{{- end }}

{{/*
Prepare the k0s api extraArgs with defaults
Required arguments:
1. .Values.k0s dict
*/}}
{{- define "k0sAPIExtraArgs" -}}
{{- $admissionPlugins := list }}
{{- $args := dict
    "anonymous-auth" "true"
    "encryption-provider-config" "/var/lib/k0s/encryption.cfg"
    "authentication-config" "/var/lib/k0s/oidc-config.yaml"
    "profiling" (default false .api.profilingEnabled | toString )
    "request-timeout" (default "1m0s" .api.requestTimeout)
    "service-node-port-range" .network.nodePortRange
}}
{{- with .api.tlsCipherSuites }}
    {{- $_ := set $args "tls-cipher-suites" ( . | join ",") }}
{{- end }}
{{- if .api.audit.enabled }}
    {{- $_ := set $args "audit-log-path" (default "/var/log/k0s/audit/mke4_audit.log" .api.audit.logPath) }}
    {{- $_ := set $args "audit-log-maxage" (default 30 .api.audit.maxAge | toString) }}
    {{- $_ := set $args "audit-log-maxbackup" (default 10 .api.audit.maxBackup | toString) }}
    {{- $_ := set $args "audit-log-maxsize" (default 10 .api.audit.maxSize | toString) }}
    {{- $_ := set $args "audit-policy-file" (default "/var/lib/k0s/mke4_audit_policy.yaml" .api.audit.policyFile) }}
    {{- if .api.audit.webhookConfigSecret }}
        {{- $_ := set $args "audit-webhook-config-file" "/var/log/k0s/audit/webhook-config.yaml" }}
    {{- end }}
{{- end }}
{{- if .api.eventRateLimit.enabled }}
    {{- $admissionPlugins = append $admissionPlugins "EventRateLimit" }}
    {{- $_ := set $args "admission-control-config-file" "/var/lib/k0s/event_rate_limit_config.yaml" }}
{{- end }}
{{- if .api.alwaysPullImages }}
    {{- $admissionPlugins = append $admissionPlugins "AlwaysPullImages" }}
{{- end }}
{{- if gt (len $admissionPlugins) 0 }}
    {{- $_ := set $args "enable-admission-plugins" (join "," $admissionPlugins) }}
{{- end }}
{{- $args = mergeOverwrite $args .api.extraArgs }}
{{- toYaml $args }}
{{- end }}

{{/*
Prepare the k0s controllerManager extraArgs with defaults
Required arguments:
1. .Values.k0s.controllerManager dict
*/}}
{{- define "k0sControllerManagerExtraArgs" -}}
{{- $args := dict
    "profiling" (toString .profilingEnabled)
    "terminated-pod-gc-threshold" (default 12500 .terminatedPodGCThreshold | toString)
}}
{{- $args = mergeOverwrite $args .extraArgs }}
{{- toYaml $args }}
{{- end }}

{{/*
Prepare the k0s kubelet args install flag
Required arguments:
1. .Values.k0s.kubelet.extraArgs dict
*/}}
{{- define "kubeletArgs" -}}
{{- $argsList := list }}
{{- range $key,$value := . }}
    {{- $argsList = append $argsList (printf "--%s=%s" $key $value) }}
{{- end }}
{{- join " " $argsList | quote }}
{{- end }}

{{/*
Prepare the OpenStack API load balancer configuration with defaults
Required arguments:
1. .Values.apiServerLoadBalancer
*/}}
{{- define "apiLoadBalancer" -}}
{{- $apiServerLoadBalancer := default dict . }}
{{- $additionalPorts := default list $apiServerLoadBalancer.additionalPorts }}
{{- $containsMKEPort := false }}
{{- range $port := $additionalPorts }}
    {{- if eq "33001" (toString $port) }}
        {{- $containsMKEPort = true }}
    {{- end }}
{{- end }}
{{- if not $containsMKEPort }}
    {{- $additionalPorts = append $additionalPorts 33001 }}
{{- end }}
{{- $_ := set $apiServerLoadBalancer "additionalPorts" $additionalPorts }}
{{- toYaml $apiServerLoadBalancer }}
{{- end }}
