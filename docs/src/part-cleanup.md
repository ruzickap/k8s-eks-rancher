# Clean-up

<!-- toc -->

![Clean-up](https://raw.githubusercontent.com/aws-samples/eks-workshop/65b766c494a5b4f5420b2912d8373c4957163541/static/images/cleanup.svg?sanitize=true
"Clean-up")

Install necessary software:

```bash
if command -v apt-get &> /dev/null; then
  apt update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl jq sudo unzip > /dev/null
fi
```

Install [eksctl](https://eksctl.io/):

```bash
if ! command -v eksctl &> /dev/null; then
  # renovate: datasource=github-tags depName=eksctl lookupName=weaveworks/eksctl
  EKSCTL_VERSION="0.97.0"
  curl -s -L "https://github.com/weaveworks/eksctl/releases/download/v${EKSCTL_VERSION}/eksctl_$(uname)_amd64.tar.gz" | sudo tar xz -C /usr/local/bin/
fi
```

Install [AWS CLI](https://aws.amazon.com/cli/) binary:

```bash
if ! command -v aws &> /dev/null; then
  # renovate: datasource=github-tags depName=awscli lookupName=aws/aws-cli
  AWSCLI_VERSION="2.7.1"
  curl -sL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWSCLI_VERSION}.zip" -o "/tmp/awscli.zip"
  unzip -q -o /tmp/awscli.zip -d /tmp/
  sudo /tmp/aws/install
fi
```

Install [kubectl](https://github.com/kubernetes/kubectl) binary:

```bash
if ! command -v kubectl &> /dev/null; then
  # renovate: datasource=github-tags depName=kubernetes/kubectl extractVersion=^kubernetes-(?<version>.+)$
  KUBECTL_VERSION="1.30.1"
  sudo curl -s -Lo /usr/local/bin/kubectl "https://storage.googleapis.com/kubernetes-release/release/v${KUBECTL_VERSION}/bin/$(uname | sed "s/./\L&/g")/amd64/kubectl"
  sudo chmod a+x /usr/local/bin/kubectl
fi
```

Set necessary variables and verify if all the necessary variables were set:

```bash
# AWS Region
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-eu-central-1}"
# Hostname / FQDN definitions
export CLUSTER_FQDN="${CLUSTER_FQDN:-mgmt1.k8s.use1.dev.proj.aws.mylabs.dev}"
export BASE_DOMAIN="${CLUSTER_FQDN#*.}"
export CLUSTER_NAME="${CLUSTER_FQDN%%.*}"
export KUBECONFIG="${PWD}/tmp/${CLUSTER_FQDN}/kubeconfig-${CLUSTER_NAME}.conf"

: "${AWS_ACCESS_KEY_ID?}"
: "${AWS_DEFAULT_REGION?}"
: "${AWS_SECRET_ACCESS_KEY?}"
: "${BASE_DOMAIN?}"
: "${CLUSTER_FQDN?}"
: "${CLUSTER_NAME?}"
: "${KUBECONFIG?}"
```

Remove EKS cluster and created components:

```bash
if eksctl get cluster --name="${CLUSTER_NAME}" 2> /dev/null; then
  eksctl utils write-kubeconfig --cluster="${CLUSTER_NAME}" --kubeconfig "${KUBECONFIG}"
  eksctl delete cluster --name="${CLUSTER_NAME}" --force
fi
```

Remove orphan EC2 created by Karpenter:

```bash
while read -r EC2; do
  echo "Removing EC2: ${EC2}"
  aws ec2 terminate-instances --instance-ids "${EC2}"
done < <(aws ec2 describe-instances --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" Name=instance-state-name,Values=running --query "Reservations[].Instances[].InstanceId" --output text)
```

Remove orphan ELBs, NLBs (if exists):

```bash
# Remove Network ELBs
while read -r NETWORK_ELB_ARN; do
  if [[ "$(aws elbv2 describe-tags --resource-arns "${NETWORK_ELB_ARN}" --query "TagDescriptions[].Tags[?Key == \`kubernetes.io/cluster/${CLUSTER_NAME}\`]" --output text)" =~ ${CLUSTER_NAME} ]]; then
    echo "Deleting Network ELB: ${NETWORK_ELB_ARN}"
    aws elbv2 delete-load-balancer --load-balancer-arn "${NETWORK_ELB_ARN}"
  fi
done < <(aws elbv2 describe-load-balancers --query "LoadBalancers[].LoadBalancerArn" --output=text)

# Remove Classic ELBs
while read -r CLASSIC_ELB_NAME; do
  if [[ "$(aws elb describe-tags --load-balancer-names "${CLASSIC_ELB_NAME}" --query "TagDescriptions[].Tags[?Key == \`kubernetes.io/cluster/${CLUSTER_NAME}\`]" --output text)" =~ ${CLUSTER_NAME} ]]; then
    echo "💊 Deleting Classic ELB: ${CLASSIC_ELB_NAME}"
    aws elb delete-load-balancer --load-balancer-name "${CLASSIC_ELB_NAME}"
  fi
done < <(aws elb describe-load-balancers --query "LoadBalancerDescriptions[].LoadBalancerName" --output=text)
```

Remove Route 53 DNS records from DNS Zone:

```bash
CLUSTER_FQDN_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name==\`${CLUSTER_FQDN}.\`].Id" --output text)
if [[ -n "${CLUSTER_FQDN_ZONE_ID}" ]]; then
  aws route53 list-resource-record-sets --hosted-zone-id "${CLUSTER_FQDN_ZONE_ID}" | jq -c '.ResourceRecordSets[] | select (.Type != "SOA" and .Type != "NS")' |
    while read -r RESOURCERECORDSET; do
      aws route53 change-resource-record-sets \
        --hosted-zone-id "${CLUSTER_FQDN_ZONE_ID}" \
        --change-batch '{"Changes":[{"Action":"DELETE","ResourceRecordSet": '"${RESOURCERECORDSET}"' }]}' \
        --output text --query 'ChangeInfo.Id'
    done
fi
```

Remove CloudFormation stacks:

```bash
aws cloudformation delete-stack --stack-name "${CLUSTER_NAME}-route53"
```

Remove Volumes and Snapshots related to the cluster:

```bash
while read -r VOLUME; do
  echo "Removing Volume: ${VOLUME}"
  aws ec2 delete-volume --volume-id "${VOLUME}"
done < <(aws ec2 describe-volumes --filters "Name=tag:Cluster,Values=${CLUSTER_FQDN}" --query 'Volumes[].VolumeId' --output text)

while read -r SNAPSHOT; do
  echo "Removing Snapshot: ${SNAPSHOT}"
  aws ec2 delete-snapshot --snapshot-id "${SNAPSHOT}"
done < <(aws ec2 describe-snapshots --filter "Name=tag:Cluster,Values=${CLUSTER_FQDN}" --query 'Snapshots[].SnapshotId' --output text)
```

Wait for all CloudFormation stacks to be deleted:

```bash
aws cloudformation wait stack-delete-complete --stack-name "${CLUSTER_NAME}-route53"
aws cloudformation wait stack-delete-complete --stack-name "eksctl-${CLUSTER_NAME}-cluster"
```

Remove `tmp/${CLUSTER_FQDN}` directory:

```bash
rm -rf "tmp/${CLUSTER_FQDN}"
```

Clean-up completed:

```bash
echo "Cleanup completed..."
```
