local promxy = (import '../promxy.libsonnet');

promxy({
    local p = self,
    namespace: 'monitoring',
    replicas: 3,
    version: '0.0.73',
    image: 'quay.io/jacksontj/promxy:v%s' % p.version,
    queryTimeout: '10m',
    serviceMonitor: true,
    resources: {
      limits: {
        cpu: "20",
        memory: '25Gi'
      },
      requests: {
        cpu: "3",
        memory: '8Gi'
      },
    },  
  })