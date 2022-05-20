# Install Kubernetes basic cluster components

<!-- toc -->

## cert-manager

Install `cert-manager`
[helm chart](https://artifacthub.io/packages/helm/jetstack/cert-manager)
and modify the
[default values](https://github.com/jetstack/cert-manager/blob/master/deploy/charts/cert-manager/values.yaml).
Service account `cert-manager` was created by `eksctl`.

```bash
# renovate: datasource=helm depName=cert-manager packageName=cert-manager registryUrl=https://charts.jetstack.io
CERT_MANAGER_HELM_CHART_VERSION="v1.7.0"

helm repo add --force-update jetstack https://charts.jetstack.io
helm upgrade --install --version "${CERT_MANAGER_HELM_CHART_VERSION}" --namespace cert-manager --create-namespace --wait --values - cert-manager jetstack/cert-manager << EOF
installCRDs: true
serviceAccount:
  create: false
  name: cert-manager
extraArgs:
  - --enable-certificate-owner-ref=true
EOF
```

## Rancher

Create `cattle-system` namespace

```bash
kubectl get namespace cattle-system &> /dev/null || kubectl create namespace cattle-system
```

Prepare `tls-ca-additional` secret with Let's Encrypt staging certificate:

```bash
kubectl get -n cattle-system secret tls-ca &> /dev/null || kubectl -n cattle-system create secret generic tls-ca --from-literal=cacerts.pem="$(curl -sL https://letsencrypt.org/certs/staging/letsencrypt-stg-root-x1.pem)"
```

Install `rancher-server`
[helm chart](https://github.com/rancher/rancher/tree/master/chart)
and modify the
[default values](https://github.com/rancher/rancher/blob/master/chart/values.yaml).

```bash
# renovate: datasource=helm depName=rancher packageName=rancher registryUrl=https://releases.rancher.com/server-charts/latest
RANCHER_HELM_CHART_VERSION="2.6.4"

helm repo add --force-update rancher-latest https://releases.rancher.com/server-charts/latest
helm upgrade --install --version "v${RANCHER_HELM_CHART_VERSION}" --namespace cattle-system --wait --values - rancher rancher-latest/rancher << EOF
hostname: rancher.${CLUSTER_FQDN}
ingress:
  tls:
    source: letsEncrypt
letsEncrypt:
  email: ${MY_EMAIL}
  environment: ${LETSENCRYPT_ENVIRONMENT}
privateCA: true
replicas: 1
bootstrapPassword: "${MY_PASSWORD}"
EOF
```
