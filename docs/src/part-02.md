# Create additional AWS structure and Amazon EKS

<!-- toc -->

## Create Route53

Create CloudFormation template containing policies for Route53 and Domain.

Put new domain `CLUSTER_FQDN` to the Route 53 and configure the DNS delegation
from the `BASE_DOMAIN`.

Create temporary directory for files used for creating/configuring EKS Cluster
and it's components:

```bash
mkdir -p "tmp/${CLUSTER_FQDN}"
```

Create Route53 zone:

```bash
cat > "tmp/${CLUSTER_FQDN}/cf-route53.yml" << \EOF
AWSTemplateFormatVersion: 2010-09-09
Description: Route53 entries

Parameters:

  BaseDomain:
    Description: "Base domain where cluster domains + their subdomains will live. Ex: k8s.mylabs.dev"
    Type: String

  ClusterFQDN:
    Description: "Cluster FQDN. (domain for all applications) Ex: kube1.k8s.mylabs.dev"
    Type: String

Resources:

  HostedZone:
    Type: AWS::Route53::HostedZone
    Properties:
      Name: !Ref ClusterFQDN

  RecordSet:
    Type: AWS::Route53::RecordSet
    Properties:
      HostedZoneName: !Sub "${BaseDomain}."
      Name: !Ref ClusterFQDN
      Type: NS
      TTL: 60
      ResourceRecords: !GetAtt HostedZone.NameServers
EOF

if [[ $(aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE --query "StackSummaries[?starts_with(StackName, \`${CLUSTER_NAME}-route53\`) == \`true\`].StackName" --output text) == "" ]]; then
  # shellcheck disable=SC2001
  eval aws cloudformation "create-stack" \
    --parameters "ParameterKey=BaseDomain,ParameterValue=${BASE_DOMAIN} ParameterKey=ClusterFQDN,ParameterValue=${CLUSTER_FQDN}" \
    --stack-name "${CLUSTER_NAME}-route53" \
    --template-body "file://tmp/${CLUSTER_FQDN}/cf-route53.yml" \
    --tags "$(echo "${TAGS}" | sed  -e 's/\([^ =]*\)=\([^ ]*\)/Key=\1,Value=\2/g')" || true
fi
```

## Create Amazon EKS

![EKS](https://raw.githubusercontent.com/aws-samples/eks-workshop/65b766c494a5b4f5420b2912d8373c4957163541/static/images/3-service-animated.gif
"EKS")

Create [Amazon EKS](https://aws.amazon.com/eks/) in AWS by using [eksctl](https://eksctl.io/).

![eksctl](https://raw.githubusercontent.com/weaveworks/eksctl/c365149fc1a0b8d357139cbd6cda5aee8841c16c/logo/eksctl.png
"eksctl")

Create the Amazon EKS cluster with Calico using `eksctl`:

```bash
cat > "tmp/${CLUSTER_FQDN}/eksctl-${CLUSTER_NAME}.yaml" << EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: ${CLUSTER_NAME}
  region: ${AWS_DEFAULT_REGION}
  version: "1.22"
  tags: &tags
    karpenter.sh/discovery: ${CLUSTER_NAME}
$(echo "${TAGS}" | sed "s/ /\\n    /g; s/^/    /g; s/=/: /g")
iam:
  withOIDC: true
  serviceAccounts:
    - metadata:
        name: cert-manager
        namespace: cert-manager
      wellKnownPolicies:
        certManager: true
    - metadata:
        name: external-dns
        namespace: external-dns
      wellKnownPolicies:
        externalDNS: true
    - metadata:
        name: ebs-csi-controller-sa
        namespace: aws-ebs-csi-driver
      wellKnownPolicies:
        ebsCSIController: true
karpenter:
  version: 0.10.0
  createServiceAccount: true
managedNodeGroups:
  - name: ${CLUSTER_NAME}-ng
    amiFamily: Bottlerocket
    instanceType: t3.medium
    desiredCapacity: 2
    minSize: 2
    maxSize: 5
    volumeSize: 30
    tags:
      <<: *tags
      compliance:na:defender: bottlerocket
    volumeEncrypted: true
    disableIMDSv1: true
EOF

if [[ ! -s "${KUBECONFIG}" ]] ; then
  if  ! eksctl get clusters --name="${CLUSTER_NAME}" &> /dev/null ; then
    eksctl create cluster --config-file "tmp/${CLUSTER_FQDN}/eksctl-${CLUSTER_NAME}.yaml" --kubeconfig "${KUBECONFIG}"
  else
    eksctl utils write-kubeconfig --cluster="${CLUSTER_NAME}" --kubeconfig "${KUBECONFIG}"
  fi
fi
```

## Post installation tasks

Change TTL=60 of SOA + NS records for new domain
(it can not be done in CloudFormation):

```bash
if [[ ! -s "tmp/${CLUSTER_FQDN}/route53-hostedzone-ttl.yml" ]]; then
  aws cloudformation wait stack-create-complete --stack-name "${CLUSTER_NAME}-route53"
  HOSTED_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name==\`${CLUSTER_FQDN}.\`].Id" --output text)
  RESOURCE_RECORD_SET_SOA=$(aws route53 --output json list-resource-record-sets --hosted-zone-id "${HOSTED_ZONE_ID}" --query "(ResourceRecordSets[?Type == \`SOA\`])[0]" | sed "s/\"TTL\":.*/\"TTL\": 60,/")
  RESOURCE_RECORD_SET_NS=$(aws route53 --output json list-resource-record-sets --hosted-zone-id "${HOSTED_ZONE_ID}" --query "(ResourceRecordSets[?Type == \`NS\`])[0]" | sed "s/\"TTL\":.*/\"TTL\": 60,/")
  cat << EOF | jq > "tmp/${CLUSTER_FQDN}/route53-hostedzone-ttl.yml"
{
    "Comment": "Update record to reflect new TTL for SOA and NS records",
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet":
${RESOURCE_RECORD_SET_SOA}
        },
        {
            "Action": "UPSERT",
            "ResourceRecordSet":
${RESOURCE_RECORD_SET_NS}
        }
    ]
}
EOF
  aws route53 change-resource-record-sets --output json --hosted-zone-id "${HOSTED_ZONE_ID}" --change-batch="file://tmp/${CLUSTER_FQDN}/route53-hostedzone-ttl.yml"
fi
```
