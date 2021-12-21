local vm = (import '../victoriametrics.libsonnet');

vm({
    local vm = self,
    namespace: 'monitoring',
    replicas: 3,
    version: '1.66.2',
    image: 'victoriametrics/victoria-metrics:v%s' % vm.version,
    serviceMonitor: true,
    resources: {
      limits: {
        cpu: "30",
        memory: '100Gi'
      },
      requests: {
        cpu: "8",
        memory: '20Gi'
      },
    },
    volumeClaimTemplate: {
      spec: {
        accessModes: ['ReadWriteOnce'],
        storageClassName: 'local-storage',
        resources: {
          requests: {
            storage: '200Gi',
          },
        },
      },
    },    
  })