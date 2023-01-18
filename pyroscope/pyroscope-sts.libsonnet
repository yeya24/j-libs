// These are the defaults for this components configuration.
// When calling the function to generate the component's manifest,
// you can pass an object structured like the default to overwrite default values.
local defaults = {
  local defaults = self,
  name: 'pyroscope',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  replicas: error 'must provide replicas',
  pvcSize: '200Gi',

  configPath: '/var/pyroscope/config.yaml',
  configmapName: 'pyroscope-config',
  retention: '4h',
  config: {
    'log-level': 'info',
    'retention': defaults.retention,
    'scrape-configs': [],
  },
  volumeClaimTemplate: {},

  cacheEvictThreshold: 0.2,
  cacheEvictVolume: 0.33,

  resources: {},
  port: 4040,

  serviceMonitor: false,
  storageRetentionTime: '',

  commonLabels:: {
    'app.kubernetes.io/name': 'pyroscope',
    'app.kubernetes.io/instance': defaults.name,
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/component': 'observability',
  },

  podLabelSelector:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if labelName != 'app.kubernetes.io/version'
  },

  securityContext:: {
    fsGroup: 65534,
    runAsUser: 65534,
  },
};

function(params) {
  local prc = self,

  // Combine the defaults and the passed params to make the component's config.
  config:: defaults + params,
  // Safety checks for combined config of defaults and params
  assert std.isNumber(prc.config.replicas) && prc.config.replicas >= 0 : 'pyroscope replicas has to be number >= 0',
  assert std.isObject(prc.config.resources),
  assert std.isBoolean(prc.config.serviceMonitor),

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: {
      name: prc.config.name,
      namespace: prc.config.namespace,
      labels: prc.config.commonLabels,
    },
    spec: {
      ports: [
        {
          assert std.isNumber(prc.config.port),
          name: 'http',
          port: prc.config.port,
          targetPort: prc.config.port,
        },
      ],
      selector: prc.config.podLabelSelector,
    },
  },

  serviceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: {
      name: prc.config.name,
      namespace: prc.config.namespace,
      labels: prc.config.commonLabels,
    },
  },

  clusterRole: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRole',
    metadata: {
      name: prc.config.name,
      labels: prc.config.commonLabels,
    },
    rules: [
      {
        apiGroups: [''],
        resources: ['services', 'endpoints', 'pods'],
        verbs: ['get', 'list', 'watch'],
      },
      {
        apiGroups: ['extensions'],
        resources: ['ingresses'],
        verbs: ['get', 'list', 'watch'],
      },
      {
        apiGroups: ['networking.k8s.io'],
        resources: ['ingresses'],
        verbs: ['get', 'list', 'watch'],
      },
    ],
  },

  clusterRoleBinding: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRoleBinding',
    metadata: {
      name: prc.config.name,
      labels: prc.config.commonLabels,
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: prc.config.name,
    },
    subjects: [
      {
        kind: 'ServiceAccount',
        name: prc.serviceAccount.metadata.name,
        namespace: prc.config.namespace
      },
    ],
  },

  configmap: {
    apiVersion: 'v1',
    kind: 'ConfigMap',
    metadata: {
      name: prc.config.configmapName,
      namespace: prc.config.namespace,
    },
    data: {
      'config.yaml': std.manifestYamlDoc(prc.config.config),
    },
  },

  statefulSet:
    local c = {
      name: 'pyroscope',
      image: prc.config.image,
      args:
        [
          'server',
          '--config=' + prc.config.configPath,
          '--analytics-opt-out=true',
          '--cache-evict-threshold=' + prc.config.cacheEvictThreshold,
          '--cache-evict-volume=' + prc.config.cacheEvictVolume,
        ],
      ports: [
        { name: port.name, containerPort: port.port }
        for port in prc.service.spec.ports
      ],
      volumeMounts: [
        { name: 'pyroscope-config', mountPath: '/var/pyroscope' },
        { name: 'pyroscope-data', mountPath: '/var/lib/pyroscope' },
      ],
      resources: if prc.config.resources != {} then prc.config.resources else {},
      terminationMessagePolicy: 'FallbackToLogsOnError',
      livenessProbe: {
        initialDelaySeconds: 30,
        periodSeconds: 15,
        timeoutSeconds: 30,
        successThreshold: 1,
        failureThreshold: 3,
        httpGet: {
          path: '/healthz',
          port: prc.config.port
        },
      },
      readinessProbe: {
        initialDelaySeconds: 30,
        periodSeconds: 5,
        timeoutSeconds: 30,
        successThreshold: 1,
        failureThreshold: 3,
        httpGet: {
          path: '/healthz',
          port: prc.config.port
        },
      },
    };

    {
      apiVersion: 'apps/v1',
      kind: 'StatefulSet',
      metadata: {
        name: prc.config.name,
        namespace: prc.config.namespace,
        labels: prc.config.commonLabels,
      },
      spec: {
        replicas: prc.config.replicas,
        selector: { matchLabels: prc.config.podLabelSelector },
        serviceName: prc.service.metadata.name,
        volumeClaimTemplates: if std.length(prc.config.volumeClaimTemplate) > 0 then [prc.config.volumeClaimTemplate {
          metadata+: {
            name: 'pyroscope-data',
            labels+: prc.config.podLabelSelector,
          },
        }] else [],
        template: {
          metadata: {
            labels: prc.config.commonLabels,
          },
          spec: {
            containers: [c],
            securityContext: prc.config.securityContext,
            serviceAccountName: prc.serviceAccount.metadata.name,
            terminationGracePeriodSeconds: 10,
            volumes: [
              {
                name: 'pyroscope-config',
                configMap: { name: prc.config.configmapName },
              },
            ],
            nodeSelector: {
              'kubernetes.io/os': 'linux',
              'kubernetes.io/arch': 'amd64',
            },
          },
        },
      },
    },

  serviceMonitor: if prc.config.serviceMonitor == true then {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata+: {
      name: prc.config.name,
      namespace: prc.config.namespace,
      labels: prc.config.commonLabels,
    },
    spec: {
      selector: {
        matchLabels: prc.config.podLabelSelector,
      },
      endpoints: [
        {
          port: prc.service.spec.ports[0].name,
          relabelings: [{
            sourceLabels: ['namespace', 'pod'],
            separator: '/',
            targetLabel: 'instance',
          }],
        },
      ],
    },
  },
}

