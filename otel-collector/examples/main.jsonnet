local oc = (import '../otel-collector.libsonnet');

oc({
    local cfg = self,
    namespace: 'monitoring',
    replicas: 1,
    version: '0.40.0',
    image: 'otel/opentelemetry-collector-contrib:' + cfg.version,
    serviceMonitor: true
})