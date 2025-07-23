
# Setup

```sh
KCM_NAMESPACE=k0rdent
REGISTRY=oci://registry.k8s.pac.dockerps.io/mke4
```

## TEMP : k0smotron provider update

There's an issue with non-root users in current k0smotron provider in the k0rdent-enterprise version provided in MKE4k 4.1.1-alpha3.  

Update the provider to the latest version (will be in k0rdent enterprise 1.1.0)

```sh
# Create the provider
kubectl -n $KCM_NAMESPACE apply -f <<EOF
apiVersion: k0rdent.mirantis.com/v1beta1
kind: ProviderTemplate
metadata:
  labels:
    k0rdent.mirantis.com/component: kcm
  name: cluster-api-provider-k0sproject-k0smotron-1-0-6
spec:
  helm:
    chartSpec:
      chart: cluster-api-provider-k0sproject-k0smotron
      interval: 10m0s
      reconcileStrategy: ChartVersion
      sourceRef:
        kind: HelmRepository
        name: kcm-templates
      version: 1.0.6
EOF

# Patch release object
kubectl -n $KCM_NAMESPACE patch release k0rdent-enterprise-1-0-0 --type='json' -p='[{"op": "replace", "path": "/spec/providers/0/template", "value": "cluster-api-provider-k0sproject-k0smotron-1-0-6"}]'

# Manually edit deployment.kcm-k0rdent-enterprise-controller-manager to set a custom download url 
replace - --global-k0s-url=https://get.mirantis.com/k0rdent-enterprise/1.0.0
with - --global-k0s-url=https://image-cache-server.k8s.pac.dockerps.io
```

## Package and upload helm charts


```sh
$ helm package templates/mke4k-remote-cluster-standalone-cp
$ helm package templates/mke-support-objects
$ helm package templates/dex-web-static

$ helm push mke4k-remote-cluster-standalone-cp-0.0.1.tgz $REGISTRY
$ helm push mke-support-objects-0.1.0.tgz $REGISTRY
$ helm push dex-web-static-0.1.0.tgz $REGISTRY

# Create new HelmRepository
kubectl -n $KCM_NAMESPACE apply -f - <<EOF
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  labels:
    k0rdent.mirantis.com/managed: "true"
  name: templates-repository
spec:
  interval: 10m0s
  provider: generic
  type: oci
  url: $REGISTRY
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  labels:
    k0rdent.mirantis.com/managed: "true"
  name: mirantiscontainers
spec:
  interval: 10m0s
  provider: generic
  type: oci
  url: $REGISTRY
EOF
```

Create ServiceTemplates

```sh
envsubst < templates/service-template-no-k0rdent.yaml | kubectl apply -f -
```

Create ClusterTemplate

```sh
kubectl -n $KCM_NAMESPACE apply -f - <<EOF
apiVersion: k0rdent.mirantis.com/v1alpha1
kind: ClusterTemplate
metadata:
  name: mke4k-remote-cluster-standalone-cp-0-0-1
  namespace: k0rdent
spec:
  helm:
    chartSpec:
      chart: mke4k-remote-cluster-standalone-cp
      interval: 10m0s
      reconcileStrategy: ChartVersion
      sourceRef:
        kind: HelmRepository
        name: templates-repository
      version: 0.0.1
EOF
```

Create credentials required to connect to virtual machines

```sh
SSH_KEY=$(cat <ssh key> | base64)

envsubst <<EOF | kubectl -n $KCM_NAMESPACE apply -f -
apiVersion: v1
data:
  value: $SSH_KEY
kind: Secret
metadata:
  annotations:
  labels:
    k0rdent.mirantis.com/component: kcm
  name: remote-ssh-key
type: Opaque
EOF

# not sure if required
kubectl -n $KCM_NAMESPACE apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  labels:
    k0rdent.mirantis.com/component: kcm
  name: remote-ssh-key-resource-template
EOF

# credential
envsubst <<EOF | kubectl -n $KCM_NAMESPACE apply -f -
apiVersion: k0rdent.mirantis.com/v1beta1
kind: Credential
metadata:
  generation: 1
  labels:
    k0rdent.mirantis.com/component: kcm
  name: remote-cred
spec:
  identityRef:
    apiVersion: v1
    kind: Secret
    name: remote-ssh-key
    namespace: $KCM_NAMESPACE
EOF
```

# ClusterDeployment

Edit and adapt contents of `remote-cld.yaml`
- `apiServerHost` with address of external load balancer
- `remoteMachines` with informations about the existing virtual machines


# Issues
- RemoteMachines are not deleted automatically when deleting the ClusterDeployment. Workaround is to first delete the Cluster, then after RemoteMachines are deleted, you can delete the ClusterDeployment
- /var/lib/kubelet is not emptied. For now, using /var/lib/k0s/kubelet while https://github.com/k0sproject/k0smotron/issues/1114 is not fixed
