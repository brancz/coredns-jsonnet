local k = import 'ksonnet/ksonnet.beta.3/k.libsonnet';

local coredns = (import 'coredns.libsonnet').coredns;

k.core.v1.list.new([
  coredns.serviceAccount,
  coredns.clusterRole,
  coredns.clusterRoleBinding,
  coredns.configMap,
  coredns.deployment,
  coredns.service,
])
