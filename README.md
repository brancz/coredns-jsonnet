# coredns-jsonnet

This repository contains [jsonnet](https://jsonnet.org/) code to render [Kubernetes](https://kubernetes.io/) manifests to run [coredns](https://coredns.io/) as the cluster's DNS provider/addon.

# Usage

```
jsonnet -J coredns/vendor -J coredns example.jsonnet
```
