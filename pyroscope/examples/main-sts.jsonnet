local p = (import '../pyroscope-sts.libsonnet');

local defaults = {
    namespace: 'monitoring',
    version: '0.36.1',   
    serviceMonitor: true,
    storageClassName: 'local-storage',
  };

p(defaults + {
    name: 'pyroscope',
    image: 'pyroscope/pyroscope:' + super.version,
    replicas: 1,
    resources: {
      requests: {
        cpu: '500m',
        memory: '8Gi',
      },
      limits: {
        cpu: '4',
        memory: '16Gi',
      },
    },
    volumeClaimTemplate: {
      spec: {
        accessModes: ['ReadWriteOnce'],
        storageClassName: defaults.storageClassName,
        resources: {
          requests: {
            storage: '200Gi',
          },
        },
      },
    },
    config+: {
      'scrape-configs': [
        {
          'job-name': 'argocd',
          'enabled-profiles': [ 'cpu', 'mem' ],
          'scrape-interval': '1m',
          'scrape-timeout': '30s',
          'kubernetes-sd-configs': [{
            role: 'pod',
            namespaces: {
              names: ['infra-argocd']
            },
          }],
          'relabel-configs': [
            {
              action: 'labelmap',
              regex: '__meta_kubernetes_pod_label_app_kubernetes_io_(.+)',
              replacement: 'app_kubernetes_io_$1'             
            },
            {
              action: 'replace',
              'source-labels': ['__meta_kubernetes_namespace'],
              'target-label': 'namespace' 
            },
            {
              action: 'replace',
              'source-labels': ['__meta_kubernetes_pod_name'],
              'target-label': 'pod' 
            },
            {
              action: 'replace',
              'source-labels': ['__meta_kubernetes_pod_container_name'],
              'target-label': 'container' 
            },
            {
              action: 'drop',
              'source-labels': ['app_kubernetes_io_component'],
              regex: 'redis'
            },
            {
              replacement: '${1}',
              'source-labels': ['app_kubernetes_io_name'],
              'target-label': '__name__',
              regex: '(.+)'
            },
          ],        
        },
        {
          'job-name': 'thanos',
          'enabled-profiles': [ 'cpu', 'mem', 'goroutine' ],
          'scrape-interval': '1m',
          'scrape-timeout': '30s',
          'kubernetes-sd-configs': [{
            role: 'pod',
            namespaces: {
              names: ['gitops-platform-metrics']
            },
          }],
          'relabel-configs': [
            {
              action: 'labelmap',
              regex: '__meta_kubernetes_pod_label_app_kubernetes_io_(.+)',
              replacement: 'app_kubernetes_io_$1'             
            },
            {
              action: 'replace',
              'source-labels': ['__meta_kubernetes_namespace'],
              'target-label': 'namespace' 
            },
            {
              action: 'replace',
              'source-labels': ['__meta_kubernetes_pod_name'],
              'target-label': 'pod' 
            },
            {
              action: 'replace',
              'source-labels': ['__meta_kubernetes_pod_container_name'],
              'target-label': 'container' 
            },
            {
              action: 'keep',
              'regex': 'prometheus|thanos-.*',
              'source-labels': ['container'],
            },
            {
              replacement: '${1}',
              'source-labels': ['app_kubernetes_io_name'],
              'target-label': '__name__',
              regex: '(.+)'
            },
          ],        
        },
      ],
    },    
  })