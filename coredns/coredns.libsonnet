local k = import 'ksonnet/ksonnet.beta.3/k.libsonnet';

{
  _config+:: {
    namespace: 'kube-system',

    imageRepos+:: {
      coredns: 'coredns/coredns',
    },

    versions+:: {
      coredns: '1.1.3',
    },

    coredns+:: {
      clusterDomain: 'cluster.local',
      reverseCIDRs: 'in-addr.arpa ip6.arpa',
      clusterIP: '10.3.0.10',
    },
  },
  coredns+:: {
    serviceAccount:
      local serviceAccount = k.core.v1.serviceAccount;

      serviceAccount.new('coredns') +
      serviceAccount.mixin.metadata.withNamespace($._config.namespace),
    clusterRole:
      local clusterRole = k.rbac.v1.clusterRole;
      local policyRule = clusterRole.rulesType;

      local coreRule = policyRule.new() +
                       policyRule.withApiGroups(['']) +
                       policyRule.withResources([
                         'endpoints',
                         'services',
                         'pods',
                         'namespaces',
                       ]) +
                       policyRule.withVerbs(['list', 'watch']);

      clusterRole.new() +
      clusterRole.mixin.metadata.withName('system:coredns') +
      clusterRole.mixin.metadata.withLabels({ 'kubernetes.io/bootstrapping': 'rbac-defaults' }) +
      clusterRole.withRules(coreRule),
    clusterRoleBinding:
      local clusterRoleBinding = k.rbac.v1.clusterRoleBinding;

      clusterRoleBinding.new() +
      clusterRoleBinding.mixin.metadata.withName('system:coredns') +
      clusterRoleBinding.mixin.metadata.withAnnotations({ 'rbac.authorization.kubernetes.io/autoupdate': 'true' }) +
      clusterRoleBinding.mixin.metadata.withLabels({ 'kubernetes.io/bootstrapping': 'rbac-defaults' }) +
      clusterRoleBinding.mixin.roleRef.withApiGroup('rbac.authorization.k8s.io') +
      clusterRoleBinding.mixin.roleRef.withName('system:coredns') +
      clusterRoleBinding.mixin.roleRef.mixinInstance({ kind: 'ClusterRole' }) +
      clusterRoleBinding.withSubjects([{ kind: 'ServiceAccount', name: 'coredns', namespace: $._config.namespace }]),
    configMap:
      local configMap = k.core.v1.configMap;

      configMap.new('coredns', {
        Corefile: |||
          .:53 {
          	errors
          	health
          	kubernetes %(clusterDomain)s %(reverseCIDRs)s {
          	  pods insecure
          	  upstream
          	  fallthrough in-addr.arpa ip6.arpa
          	}
          	prometheus :9153
          	proxy . /etc/resolv.conf
          	cache 30
          	reload
          }
        ||| % $._config.coredns,
      }) +
      configMap.mixin.metadata.withNamespace($._config.namespace),
    deployment:
      local deployment = k.apps.v1beta2.deployment;
      local container = k.apps.v1beta2.deployment.mixin.spec.template.spec.containersType;
      local volume = k.apps.v1beta2.deployment.mixin.spec.template.spec.volumesType;
      local containerPort = container.portsType;
      local containerVolumeMount = container.volumeMountsType;

      local podLabels = { 'k8s-app': 'kube-dns' };
      local configVolumeName = 'config-volume';

      local configVolume = volume.fromConfigMap(configVolumeName, $.coredns.configMap.metadata.name, { key: 'Corefile', path: 'Corefile' });
      local configVolumeMount = containerVolumeMount.new(configVolumeName, '/etc/coredns');

      local portDns = containerPort.newNamed('dns', 53) +
                      containerPort.withProtocol('UDP');

      local portDnsTcp = containerPort.newNamed('dns-tcp', 53) +
                         containerPort.withProtocol('TCP');

      local portMetrics = containerPort.newNamed('metrics', 9153) +
                          containerPort.withProtocol('TCP');

      local ports = [portDns, portDnsTcp, portMetrics];

      local c =
        container.new('coredns', $._config.imageRepos.coredns + ':' + $._config.versions.coredns) +
        container.withArgs('-conf=/etc/coredns/Corefile') +
        container.withVolumeMounts(configVolumeMount) +
        container.withPorts(ports) +
        container.mixin.securityContext.withAllowPrivilegeEscalation(false) +
        container.mixin.securityContext.withReadOnlyRootFilesystem(true) +
        container.mixin.securityContext.capabilities.withAdd('NET_BIND_SERVICE') +
        container.mixin.securityContext.capabilities.withDrop('all') +
        container.mixin.livenessProbe.httpGet.withPath('/health') +
        container.mixin.livenessProbe.httpGet.withPort(8080) +
        container.mixin.livenessProbe.httpGet.withScheme('HTTP') +
        container.mixin.livenessProbe.withInitialDelaySeconds(60) +
        container.mixin.livenessProbe.withTimeoutSeconds(5) +
        container.mixin.livenessProbe.withSuccessThreshold(1) +
        container.mixin.livenessProbe.withFailureThreshold(5);

      deployment.new('coredns', 2, c, podLabels) +
      deployment.mixin.metadata.withNamespace($._config.namespace) +
      deployment.mixin.metadata.withLabels(podLabels) +
      deployment.mixin.spec.selector.withMatchLabels(podLabels) +
      deployment.mixin.spec.template.spec.withDnsPolicy('Default') +
      deployment.mixin.spec.template.spec.withVolumes(configVolume) +
      deployment.mixin.spec.template.spec.withServiceAccountName($.coredns.serviceAccount.metadata.name),
    service:
      local service = k.core.v1.service;
      local servicePort = k.core.v1.service.mixin.spec.portsType;

      local corednsServicePortDns = servicePort.newNamed('dns', 53, 'dns') +
                                    servicePort.withProtocol('UDP');

      local corednsServicePortDnsTcp = servicePort.newNamed('dns-tcp', 53, 'dns-tcp') +
                                       servicePort.withProtocol('TCP');

      local corednsServicePortMetrics = servicePort.newNamed('metrics', 9153, 'metrics') +
                                        servicePort.withProtocol('TCP');

      local ports = [
        corednsServicePortDns,
        corednsServicePortDnsTcp,
        corednsServicePortMetrics,
      ];

      service.new('kube-dns', $.coredns.deployment.spec.selector.matchLabels, ports) +
      service.mixin.metadata.withLabels({
        'k8s-app': 'kube-dns',
        'kubernetes.io/cluster-service': 'true',
        'kubernetes.io/name': 'CoreDNS',
      }) +
      service.mixin.metadata.withNamespace($._config.namespace) +
      service.mixin.spec.withClusterIp($._config.coredns.clusterIP),
  },
}
