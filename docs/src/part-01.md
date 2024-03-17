# Prepare AWS Account

<!-- toc -->

## Requirements

If you would like to follow this documents and it's task you will need to set up
few environment variables.

`BASE_DOMAIN` (`k8s.mylabs.dev`) contains DNS records for all your Kubernetes
clusters. The cluster names will look like `CLUSTER_NAME`.`BASE_DOMAIN`
(`kube1.k8s.mylabs.dev`).

```bash
# AWS Region
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-eu-central-1}"
# Hostname / FQDN definitions
export CLUSTER_FQDN="${CLUSTER_FQDN:-mgmt1.k8s.use1.dev.proj.aws.mylabs.dev}"
export BASE_DOMAIN="${CLUSTER_FQDN#*.}"
export CLUSTER_NAME="${CLUSTER_FQDN%%.*}"
export KUBECONFIG="${PWD}/tmp/${CLUSTER_FQDN}/kubeconfig-${CLUSTER_NAME}.conf"
export LETSENCRYPT_ENVIRONMENT="staging"
export MY_EMAIL="petr.ruzicka@gmail.com"
# Tags used to tag the AWS resources
export TAGS="Owner=${MY_EMAIL} Environment=dev Group=Cloud_Native Squad=Cloud_Container_Platform"
```

You will need to configure [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html)
and other secrets/variables.

```shell
# AWS Credentials
export AWS_ACCESS_KEY_ID="******************"
export AWS_SECRET_ACCESS_KEY="******************"
# Rancher password
export MY_PASSWORD="**********"
# export AWS_SESSION_TOKEN="**********"
```

Verify if all the necessary variables were set:

```bash
: "${AWS_ACCESS_KEY_ID?}"
: "${AWS_DEFAULT_REGION?}"
: "${AWS_SECRET_ACCESS_KEY?}"
: "${BASE_DOMAIN?}"
: "${CLUSTER_FQDN?}"
: "${CLUSTER_NAME?}"
: "${KUBECONFIG?}"
: "${LETSENCRYPT_ENVIRONMENT?}"
: "${MY_EMAIL?}"
: "${MY_PASSWORD}"
: "${TAGS?}"

echo -e "${MY_EMAIL} | ${CLUSTER_NAME} | ${BASE_DOMAIN} | ${CLUSTER_FQDN}\n${TAGS}"
```

## Prepare the local working environment

<!-- markdownlint-disable no-inline-html -->

<aside class="note">

<h1>Note</h1>

You can skip these steps if you have all the required software already
installed.

</aside>

Install necessary software:

```bash
if command -v apt-get &> /dev/null; then
  apt update -qq
  apt-get install -y -qq curl git jq sudo unzip > /dev/null
fi
```

Install [AWS CLI](https://aws.amazon.com/cli/) binary:

```bash
if ! command -v aws &> /dev/null; then
  # renovate: datasource=github-tags depName=aws/aws-cli
  AWSCLI_VERSION="2.15.30"
  curl -sL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWSCLI_VERSION}.zip" -o "/tmp/awscli.zip"
  unzip -q -o /tmp/awscli.zip -d /tmp/
  sudo /tmp/aws/install
fi
```

Install [eksctl](https://eksctl.io/):

```bash
if ! command -v eksctl &> /dev/null; then
  # renovate: datasource=github-tags depName=weaveworks/eksctl
  EKSCTL_VERSION="0.173.0"
  curl -s -L "https://github.com/weaveworks/eksctl/releases/download/v${EKSCTL_VERSION}/eksctl_$(uname)_amd64.tar.gz" | sudo tar xz -C /usr/local/bin/
fi
```

Install [kubectl](https://github.com/kubernetes/kubectl) binary:

```bash
if ! command -v kubectl &> /dev/null; then
  # renovate: datasource=github-tags depName=kubernetes/kubectl extractVersion=^kubernetes-(?<version>.+)$
  KUBECTL_VERSION="1.29.2"
  sudo curl -s -Lo /usr/local/bin/kubectl "https://storage.googleapis.com/kubernetes-release/release/v${KUBECTL_VERSION}/bin/$(uname | sed "s/./\L&/g")/amd64/kubectl"
  sudo chmod a+x /usr/local/bin/kubectl
fi
```

Install [Helm](https://helm.sh/):

```bash
if ! command -v helm &> /dev/null; then
  # renovate: datasource=github-tags depName=helm/helm
  HELM_VERSION="3.14.3"
  curl -s https://raw.githubusercontent.com/helm/helm/master/scripts/get | bash -s -- --version "v${HELM_VERSION}"
fi
```

## Configure AWS Route 53 Domain delegation

> DNS delegation should be done only once.

Create DNS zone for EKS clusters:

```shell
export CLOUDFLARE_EMAIL="petr.ruzicka@gmail.com"
export CLOUDFLARE_API_KEY="11234567890"

aws route53 create-hosted-zone --output json \
  --name "${BASE_DOMAIN}" \
  --caller-reference "$(date)" \
  --hosted-zone-config="{\"Comment\": \"Created by petr.ruzicka@gmail.com\", \"PrivateZone\": false}" | jq
```

Use your domain registrar to change the nameservers for your zone (for example
`mylabs.dev`) to use the Amazon Route 53 nameservers. Here is the way how you
can find out the the Route 53 nameservers:

```shell
NEW_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name==\`${BASE_DOMAIN}.\`].Id" --output text)
NEW_ZONE_NS=$(aws route53 get-hosted-zone --output json --id "${NEW_ZONE_ID}" --query "DelegationSet.NameServers")
NEW_ZONE_NS1=$(echo "${NEW_ZONE_NS}" | jq -r ".[0]")
NEW_ZONE_NS2=$(echo "${NEW_ZONE_NS}" | jq -r ".[1]")
```

Create the NS record in `k8s.use1.dev.proj.aws.mylabs.dev` (`BASE_DOMAIN`) for
proper zone delegation. This step depends on your domain registrar - I'm using
CloudFlare and using Ansible to automate it:

```shell
ansible -m cloudflare_dns -c local -i "localhost," localhost -a "zone=mylabs.dev record=${BASE_DOMAIN} type=NS value=${NEW_ZONE_NS1} solo=true proxied=no account_email=${CLOUDFLARE_EMAIL} account_api_token=${CLOUDFLARE_API_KEY}"
ansible -m cloudflare_dns -c local -i "localhost," localhost -a "zone=mylabs.dev record=${BASE_DOMAIN} type=NS value=${NEW_ZONE_NS2} solo=false proxied=no account_email=${CLOUDFLARE_EMAIL} account_api_token=${CLOUDFLARE_API_KEY}"
```

Output:

```text
localhost | CHANGED => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python"
    },
    "changed": true,
    "result": {
        "record": {
            "content": "ns-885.awsdns-46.net",
            "created_on": "2020-11-13T06:25:32.18642Z",
            "id": "dxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxb",
            "locked": false,
            "meta": {
                "auto_added": false,
                "managed_by_apps": false,
                "managed_by_argo_tunnel": false,
                "source": "primary"
            },
            "modified_on": "2020-11-13T06:25:32.18642Z",
            "name": "k8s.mylabs.dev",
            "proxiable": false,
            "proxied": false,
            "ttl": 1,
            "type": "NS",
            "zone_id": "2xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxe",
            "zone_name": "mylabs.dev"
        }
    }
}
localhost | CHANGED => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python"
    },
    "changed": true,
    "result": {
        "record": {
            "content": "ns-1692.awsdns-19.co.uk",
            "created_on": "2020-11-13T06:25:37.605605Z",
            "id": "9xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxb",
            "locked": false,
            "meta": {
                "auto_added": false,
                "managed_by_apps": false,
                "managed_by_argo_tunnel": false,
                "source": "primary"
            },
            "modified_on": "2020-11-13T06:25:37.605605Z",
            "name": "k8s.mylabs.dev",
            "proxiable": false,
            "proxied": false,
            "ttl": 1,
            "type": "NS",
            "zone_id": "2xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxe",
            "zone_name": "mylabs.dev"
        }
    }
}
```

## Allow GH Actions to connect to AWS accounts

You also need to allow GitHub Action to connect to the AWS account(s) where you
want to provision the clusters.

Example: [AWS federation comes to GitHub Actions](https://awsteele.com/blog/2021/09/15/aws-federation-comes-to-github-actions.html)

```shell
aws cloudformation deploy --region=eu-central-1 --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "GitHubFullRepositoryName=ruzickap/k8s-eks-rancher" \
  --stack-name "${USER}-k8s-eks-rancher-gh-action-iam-role-oidc" \
  --template-file "./cloudformation/gh-action-iam-role-oidc.yaml" \
  --tags "Owner=petr.ruzicka@gmail.com"
```
