// These are the defaults for this components configuration.
// When calling the function to generate the component's manifest,
// you can pass an object structured like the default to overwrite default values.
local defaults = {
  local defaults = self,
  name: 'promxy',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide image',
  resources: {},
  ports: {
      http: 8082,
  },
  serviceMonitor: false,
  logLevel: 'info',
  logFormat: 'logfmt',
  queryTimeout: '10m',
  lookbackDelta: '5m',
  reloaderImage: 'jimmidyson/configmap-reload:v0.1',

  config: {
      promxy: {
          server_groups: [
              {
                  kubernetes_sd_configs: [{
                    role: 'pod',
                    namespaces: {
                        names: [defaults.namespace],
                    },
                  }],
                  relabel_configs: [
                      {
                          source_labels: ['__meta_kubernetes_pod_label_app_kubernetes_io_instance'],
                          regex: 'victoria-metrics',
                          action: 'keep',
                      },
                  ],
              },
          ],
      },
  },

  commonLabels:: {
    'app.kubernetes.io/name': 'promxy',
    'app.kubernetes.io/instance': defaults.name,
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/component': 'query-layer',
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
  local promxy = self,

  // Combine the defaults and the passed params to make the component's config.
  config:: defaults + params,
  // Safety checks for combined config of defaults and params
  assert std.isNumber(promxy.config.replicas) && promxy.config.replicas >= 0 : 'promxy replicas has to be number >= 0',
  assert std.isObject(promxy.config.resources),
  assert std.isBoolean(promxy.config.serviceMonitor),

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: {
      name: promxy.config.name,
      namespace: promxy.config.namespace,
      labels: promxy.config.commonLabels,
    },
    spec: {
      ports: [
        {
          assert std.isString(name),
          assert std.isNumber(promxy.config.ports[name]),

          name: name,
          port: promxy.config.ports[name],
          targetPort: promxy.config.ports[name],
        }
        for name in std.objectFields(promxy.config.ports)
      ],
      selector: promxy.config.podLabelSelector,
    },
  },

  configMap: {
    apiVersion: 'v1',
    kind: 'ConfigMap',
    metadata: {
      name: 'promxy-config',
      namespace: promxy.config.namespace,
      labels: promxy.config.commonLabels,
    },
    data: {
      'config.yaml': std.manifestYamlDoc( promxy.config.config ),
    },
  },

  serviceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: {
      name: promxy.config.name,
      namespace: promxy.config.namespace,
      labels: promxy.config.commonLabels,
    },
  },

  clusterRole: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRole',
    metadata: {
      name: promxy.config.name,
      labels: promxy.config.commonLabels,
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
      name: promxy.config.name,
      labels: promxy.config.commonLabels,
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: promxy.config.name,
    },
    subjects: [
      {
        kind: 'ServiceAccount',
        name: promxy.serviceAccount.metadata.name,
        namespace: promxy.config.namespace
      },
    ],
  },

  deployment:
    local c = {
      name: 'promxy',
      image: promxy.config.image,
      command: ["/bin/promxy"],
      args:
        [
          '--bind-addr=0.0.0.0:%d' % promxy.config.ports.http,
          '--log-level=' + promxy.config.logLevel,
          '--log-format=default',
          "--config=/etc/promxy/config.yaml",
          "--web.enable-lifecycle",
        ] +
        (
          if promxy.config.queryTimeout != '' then [
            '--query.timeout=' + promxy.config.queryTimeout,
          ] else []
        ) +
        (
          if promxy.config.lookbackDelta != '' then [
            '--query.lookback-delta=' + promxy.config.lookbackDelta,
          ] else []
        ),
      env: [
        {
          // Inject the host IP to make configuring tracing convenient.
          name: 'HOST_IP_ADDRESS',
          valueFrom: {
            fieldRef: {
              fieldPath: 'status.hostIP',
            },
          },
        },
      ],
      ports: [
        {
          assert std.isString(name),
          assert std.isNumber(promxy.config.ports[name]),

          name: name,
          containerPort: promxy.config.ports[name],
        }
        for name in std.objectFields(promxy.config.ports)
      ],
      livenessProbe: { successThreshold: 1, timeoutSeconds: 3, failureThreshold: 6, periodSeconds: 5, httpGet: {
        scheme: 'HTTP',
        port: promxy.config.ports.http,
        path: '/-/healthy',
      } },
      readinessProbe: { successThreshold: 1, timeoutSeconds: 3, failureThreshold: 120, periodSeconds: 5, httpGet: {
        scheme: 'HTTP',
        port: promxy.config.ports.http,
        path: '/-/ready',
      } },
      resources: if promxy.config.resources != {} then promxy.config.resources else {},
      volumeMounts: [{
          mountPath: '/etc/promxy/',
          name: 'promxy-config',
          readOnly: true,
      }],
      terminationMessagePolicy: 'FallbackToLogsOnError',
    };

    local reloader = {
        name: 'config-reloader',
        image: promxy.config.reloaderImage,
        args: [
            '--volume-dir=/etc/promxy',
            '--webhook-url=http://localhost:8082/-/reload'
        ],
        volumeMounts: [
            {
                mountPath: '/etc/promxy/',
                name: 'promxy-config',
                readOnly: true,
            },
        ],
    };

    {
      apiVersion: 'apps/v1',
      kind: 'Deployment',
      metadata: {
        name: promxy.config.name,
        namespace: promxy.config.namespace,
        labels: promxy.config.commonLabels,
      },
      spec: {
        replicas: promxy.config.replicas,
        selector: { matchLabels: promxy.config.podLabelSelector },
        template: {
          metadata: {
            labels: promxy.config.commonLabels,
          },
          spec: {
            containers: [c, reloader],
            securityContext: promxy.config.securityContext,
            serviceAccountName: promxy.serviceAccount.metadata.name,
            terminationGracePeriodSeconds: 120,
            nodeSelector: {
              'kubernetes.io/os': 'linux',
            },
            volumes: [{
              name: 'promxy-config',
              configMap: { name: 'promxy-config'},
            }],
            affinity: { podAntiAffinity: {
              preferredDuringSchedulingIgnoredDuringExecution: [{
                podAffinityTerm: {
                  namespaces: [promxy.config.namespace],
                  topologyKey: 'kubernetes.io/hostname',
                  labelSelector: { matchExpressions: [{
                    key: 'app.kubernetes.io/name',
                    operator: 'In',
                    values: [promxy.deployment.metadata.labels['app.kubernetes.io/name']],
                  }] },
                },
                weight: 100,
              }],
            } },
          },
        },
      },
    },

  serviceMonitor: if promxy.config.serviceMonitor == true then {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata+: {
      name: promxy.config.name,
      namespace: promxy.config.namespace,
      labels: promxy.config.commonLabels,
    },
    spec: {
      selector: {
        matchLabels: promxy.config.podLabelSelector,
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
