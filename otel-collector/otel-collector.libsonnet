// These are the defaults for this components configuration.
// When calling the function to generate the component's manifest,
// you can pass an object structured like the default to overwrite default values.
local defaults = {
  local defaults = self,
  name: 'otel-collector',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  replicas: error 'must provide replicas',

  configPath: '/var/otel-collector/otel-collector-config.yaml',
  config: {
    receivers: {
      otlp: {
        protocols: {
          grpc: {},
          http: {},
        },
      },
    },
    processors: {
      batch: {},
    },
    exporters: {
      jaeger: {
        tls: {
          insecure: true,
        },
        endpoint: 'jaeger-collector-headless:14250',
      },
    },
    service: {
      pipelines: {
        traces: {
          receivers: ['otlp'],
          processors: ['batch'],
          exporters: ['jaeger'],
        },
      },   
    },
  },

  resources: {
    requests: {
      cpu: '200m',
      memory: '1Gi'
    },
    limits: {
      cpu: 1,
      memory: '1Gi'
    },
  },
  ports: [{name: 'otel-grpc', port: 4317}, {name: 'otel-http', port: 4318}, {name: 'metrics', port: 8888}, {name: 'jaeger', port: 14250}],

  serviceMonitor: false,

  commonLabels:: {
    'app.kubernetes.io/name': 'otel-collector',
    'app.kubernetes.io/instance': defaults.name,
    'app.kubernetes.io/version': defaults.version,
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
  local oc = self,

  // Combine the defaults and the passed params to make the component's config.
  config:: defaults + params,
  // Safety checks for combined config of defaults and params
  assert std.isNumber(oc.config.replicas) && oc.config.replicas >= 0 : 'otel collector replicas has to be number >= 0',
  assert std.isObject(oc.config.resources),
  assert std.isBoolean(oc.config.serviceMonitor),

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: {
      name: oc.config.name,
      namespace: oc.config.namespace,
      labels: oc.config.commonLabels,
    },
    spec: {
      ports: [
        {
          name: 'otlp-grpc',
          port: 4317,
          targetPort: 4317,
        },
        {
          name: 'otlp-http',
          port: 4318,
          targetPort: 4318,
        },
        {
          name: 'metrics',
          port: 8888,
          targetPort: 8888,
        },
        {
          name: 'jaeger',
          port: 14250,
          targetPort: 14250,
        }
      ],
      selector: oc.config.podLabelSelector,
    },
  },

  serviceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: {
      name: oc.config.name,
      namespace: oc.config.namespace,
      labels: oc.config.commonLabels,
    },
  },

  configmap: {
    apiVersion: 'v1',
    kind: 'ConfigMap',
    metadata: {
      name: oc.config.name + '-conf',
      namespace: oc.config.namespace,
    },
    data: {
      'otel-collector-config.yaml': std.manifestYamlDoc(oc.config.config),
    },
  },

  deployment:
    local c = {
      name: oc.config.name,
      image: oc.config.image,
      args:
        [
          '/otelcol',
          '--config=' + oc.config.configPath
        ],
      ports: [
        { name: port.name, containerPort: port.port }
        for port in oc.config.ports
      ],
      volumeMounts: [{ name: 'otel-collector-config', mountPath: '/var/otel-collector/' }],
      resources: if oc.config.resources != {} then oc.config.resources else {},
      terminationMessagePolicy: 'FallbackToLogsOnError'
    };

    {
      apiVersion: 'apps/v1',
      kind: 'Deployment',
      metadata: {
        name: oc.config.name,
        namespace: oc.config.namespace,
        labels: oc.config.commonLabels,
      },
      spec: {
        replicas: oc.config.replicas,
        selector: { matchLabels: oc.config.podLabelSelector },
        template: {
          metadata: {
            labels: oc.config.commonLabels,
          },
          spec: {
            containers: [c],
            securityContext: oc.config.securityContext,
            serviceAccountName: oc.serviceAccount.metadata.name,
            terminationGracePeriodSeconds: 10,
            volumes: [{
              name: 'otel-collector-config',
              configMap: { name: oc.configmap.metadata.name },
            }],
            nodeSelector: {
              'kubernetes.io/os': 'linux',
              'kubernetes.io/arch': 'amd64',
            },
          },
        },
      },
    },

  serviceMonitor: if oc.config.serviceMonitor == true then {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata+: {
      name: oc.config.name,
      namespace: oc.config.namespace,
      labels: oc.config.commonLabels,
    },
    spec: {
      selector: {
        matchLabels: oc.config.podLabelSelector,
      },
      endpoints: [
        {
          port: 'metrics'
        },
      ],
    },
  },
}
