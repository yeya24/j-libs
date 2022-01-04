// These are the defaults for this components configuration.
// When calling the function to generate the component's manifest,
// you can pass an object structured like the default to overwrite default values.
local defaults = {
  local defaults = self,
  name: 'vmselect',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  replicas: error 'must provide replicas',
  resources: {},
  ports: {
    http: 9090,
  },
  serviceMonitor: false,
  logLevel: 'INFO',
  logFormat: 'default',
  storageNodes: [],
  extraArgs: [],
  cacheDataPath: '/cache',
  listenAddr: ':%d' % defaults.ports.http,

  commonLabels:: {
    'app.kubernetes.io/name': 'victoria-metrics',
    'app.kubernetes.io/instance': defaults.name,
    'app.kubernetes.io/version': defaults.version,
  },

  podLabelSelector:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if labelName != 'app.kubernetes.io/version'
  },
};

function(params) {
  local vm = self,

  // Combine the defaults and the passed params to make the component's config.
  config:: defaults + params,
  // Safety checks for combined config of defaults and params
  assert std.isNumber(vm.config.replicas) && vm.config.replicas >= 0 : 'replicas has to be number >= 0',
  assert std.isObject(vm.config.resources),
  assert std.isBoolean(vm.config.serviceMonitor),

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: {
      name: vm.config.name,
      namespace: vm.config.namespace,
      labels: vm.config.commonLabels,
    },
    spec: {
      ports: [
        {
          assert std.isString(name),
          assert std.isNumber(vm.config.ports[name]),

          name: name,
          port: vm.config.ports[name],
          targetPort: vm.config.ports[name],
        }
        for name in std.objectFields(vm.config.ports)
      ],
      selector: vm.config.podLabelSelector,
    },
  },

  serviceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: {
      name: vm.config.name,
      namespace: vm.config.namespace,
      labels: vm.config.commonLabels,
    },
  },

  deployment:
    local c = {
      name: 'vmselect',
      image: vm.config.image,
      args: [
        '--cacheDataPath=%s' % vm.config.cacheDataPath,
      ] + (
          if std.length(vm.config.logLevel) > 0 
          then ['--loggerLevel=%s' % vm.config.logLevel] else []
      ) + (
          if std.length(vm.config.logFormat) > 0 
          then ['--loggerFormat=%s' % vm.config.logFormat] else []
      ) + (
          if std.length(vm.config.listenAddr) > 0 
          then ['--httpListenAddr=%s' % vm.config.listenAddr] else []
      ) + (
          if std.length(vm.config.storageNodes) > 0
          then ['--storageNode=%s' % store for store in vm.config.storageNodes ] else []
      ) + (
          if std.length(vm.config.extraArgs) > 0
          then vm.config.extraArgs else []
      ),
      ports: [
        { name: name, containerPort: vm.config.ports[name] }
        for name in std.objectFields(vm.config.ports)
      ],
      livenessProbe: { initialDelaySeconds: 30, timeoutSeconds: 5, failureThreshold: 10, periodSeconds: 30, tcpSocket: {
        port: vm.config.ports.http,
      } },
      readinessProbe: { initialDelaySeconds: 5, timeoutSeconds: 5, failureThreshold: 3, periodSeconds: 15, httpGet: {
        scheme: 'HTTP',
        port: vm.config.ports.http,
        path: '/health',
      } },
      resources: if vm.config.resources != {} then vm.config.resources else {},
      terminationMessagePolicy: 'FallbackToLogsOnError',
    };

    {
      apiVersion: 'apps/v1',
      kind: 'Deployment',
      metadata: {
        name: vm.config.name,
        namespace: vm.config.namespace,
        labels: vm.config.commonLabels,
      },
      spec: {
        replicas: vm.config.replicas,
        selector: { matchLabels: vm.config.podLabelSelector },
        template: {
          metadata: {
            labels: vm.config.commonLabels,
          },
          spec: {
            serviceAccountName: vm.serviceAccount.metadata.name,
            containers: [c],
            volumes: [],
            terminationGracePeriodSeconds: 15,
            nodeSelector: {
              'kubernetes.io/os': 'linux',
            },
            affinity: { podAntiAffinity: {
              local labelSelector = { matchExpressions: [{
                key: 'app.kubernetes.io/name',
                operator: 'In',
                values: [vm.deployment.metadata.labels['app.kubernetes.io/name']],
              }, {
                key: 'app.kubernetes.io/instance',
                operator: 'In',
                values: [vm.deployment.metadata.labels['app.kubernetes.io/instance']],
              }] },
              preferredDuringSchedulingIgnoredDuringExecution: [
                {
                  podAffinityTerm: {
                    namespaces: [vm.config.namespace],
                    topologyKey: 'kubernetes.io/hostname',
                    labelSelector: labelSelector,
                  },
                  weight: 100,
                },
                {
                  podAffinityTerm: {
                    namespaces: [vm.config.namespace],
                    topologyKey: 'topology.kubernetes.io/zone',
                    labelSelector: labelSelector,
                  },
                  weight: 100,
                },
              ],
            } },
          },
        },
      },
    },

  serviceMonitor: if vm.config.serviceMonitor == true then {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata+: {
      name: vm.config.name,
      namespace: vm.config.namespace,
      labels: vm.config.commonLabels,
    },
    spec: {
      selector: {
        matchLabels: vm.config.podLabelSelector,
      },
      endpoints: [
        {
          port: 'http',
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

