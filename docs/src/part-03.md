# Install Kubernetes basic cluster components

<!-- toc -->

## cert-manager

Install `cert-manager`
[helm chart](https://artifacthub.io/packages/helm/jetstack/cert-manager)
and modify the
[default values](https://github.com/jetstack/cert-manager/blob/master/deploy/charts/cert-manager/values.yaml).
Service account `cert-manager` was created by `eksctl`.

```bash
# renovate: datasource=helm depName=cert-manager registryUrl=https://charts.jetstack.io
CERT_MANAGER_HELM_CHART_VERSION="1.10.1"

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

Add ClusterIssuers for Let's Encrypt staging and production:

```bash
kubectl apply -f - << EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging-dns
  namespace: cert-manager
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: ${MY_EMAIL}
    privateKeySecretRef:
      name: letsencrypt-staging-dns
    solvers:
      - selector:
          dnsZones:
            - ${CLUSTER_FQDN}
        dns01:
          route53:
            region: ${AWS_DEFAULT_REGION}
---
# Create ClusterIssuer for production to get real signed certificates
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-production-dns
  namespace: cert-manager
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${MY_EMAIL}
    privateKeySecretRef:
      name: letsencrypt-production-dns
    solvers:
      - selector:
          dnsZones:
            - ${CLUSTER_FQDN}
        dns01:
          route53:
            region: ${AWS_DEFAULT_REGION}
EOF

kubectl wait --namespace cert-manager --timeout=10m --for=condition=Ready clusterissuer --all
```

## external-dns

Install `external-dns`
[helm chart](https://artifacthub.io/packages/helm/bitnami/external-dns)
and modify the
[default values](https://github.com/bitnami/charts/blob/master/bitnami/external-dns/values.yaml).
`external-dns` will take care about DNS records.
Service account `external-dns` was created by `eksctl`.

```bash
# renovate: datasource=helm depName=external-dns registryUrl=https://charts.bitnami.com/bitnami
EXTERNAL_DNS_HELM_CHART_VERSION="6.12.1"

helm repo add --force-update bitnami https://charts.bitnami.com/bitnami
helm upgrade --install --version "${EXTERNAL_DNS_HELM_CHART_VERSION}" --namespace external-dns --wait --values - external-dns bitnami/external-dns << EOF
aws:
  region: ${AWS_DEFAULT_REGION}
domainFilters:
  - ${CLUSTER_FQDN}
interval: 20s
policy: sync
serviceAccount:
  create: false
  name: external-dns
EOF
```

## ingress-nginx

Install `ingress-nginx`
[helm chart](https://artifacthub.io/packages/helm/ingress-nginx/ingress-nginx)
and modify the
[default values](https://github.com/kubernetes/ingress-nginx/blob/master/charts/ingress-nginx/values.yaml).

```bash
# renovate: datasource=helm depName=ingress-nginx registryUrl=https://kubernetes.github.io/ingress-nginx
INGRESS_NGINX_HELM_CHART_VERSION="4.4.0"

helm repo add --force-update ingress-nginx https://kubernetes.github.io/ingress-nginx
helm upgrade --install --version "${INGRESS_NGINX_HELM_CHART_VERSION}" --namespace ingress-nginx --create-namespace --wait --values - ingress-nginx ingress-nginx/ingress-nginx << EOF
controller:
  replicaCount: 2
  watchIngressWithoutClass: true
  service:
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-backend-protocol: tcp
      service.beta.kubernetes.io/aws-load-balancer-type: nlb
      service.beta.kubernetes.io/aws-load-balancer-additional-resource-tags: "$(echo "${TAGS}" | tr " " ,)"
EOF
```

## Rancher

Create Let's Encrypt certificate (using Route53):

```bash
kubectl get namespace cattle-system &> /dev/null || kubectl create namespace cattle-system

kubectl apply -f - << EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
  namespace: cattle-system
spec:
  secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
  issuerRef:
    name: letsencrypt-${LETSENCRYPT_ENVIRONMENT}-dns
    kind: ClusterIssuer
  commonName: "rancher.${CLUSTER_FQDN}"
  dnsNames:
    - "rancher.${CLUSTER_FQDN}"
EOF

kubectl wait --namespace cattle-system --for=condition=Ready --timeout=20m certificate "ingress-cert-${LETSENCRYPT_ENVIRONMENT}"
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
# renovate: datasource=helm depName=rancher registryUrl=https://releases.rancher.com/server-charts/latest
RANCHER_HELM_CHART_VERSION="2.7.0"

helm repo add --force-update rancher-latest https://releases.rancher.com/server-charts/latest
helm upgrade --install --version "v${RANCHER_HELM_CHART_VERSION}" --namespace cattle-system --wait --values - rancher rancher-latest/rancher << EOF
hostname: rancher.${CLUSTER_FQDN}
ingress:
  tls:
    source: secret
    secretName: ingress-cert-${LETSENCRYPT_ENVIRONMENT}
privateCA: true
replicas: 1
bootstrapPassword: "${MY_PASSWORD}"
EOF
```
