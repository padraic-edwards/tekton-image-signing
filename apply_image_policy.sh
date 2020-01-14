#!/bin/bash
#set -x

#source <(curl -s -S -L "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_helm_up_and_running.sh")
source <(curl -sSL "https://raw.githubusercontent.com/huayuenh/tekton-image-signing/master/check_helm_up_and_running.sh")

# Install CISE
if helm list cise | grep '^cise'; then
echo "Container Image Security Enforcement is already installed"
else
helm repo add iks-charts https://icr.io/helm/iks-charts
helm install --name cise iks-charts/ibmcloud-image-enforcement
fi

# Ensure deployment namespace is created
echo "Checking cluster namespace $CLUSTER_NAMESPACE"
if ! kubectl get namespace "$CLUSTER_NAMESPACE"; then
kubectl create namespace "$CLUSTER_NAMESPACE"
fi

# Define custom user policies
echo "Create CISE custom policies"
for signer_and_key in $(cat dct_signers.json | jq -r -c '.[] | {name:.Name, key: .Keys[0].ID}'); do
DEVOPS_SIGNER=$(echo $signer_and_key | jq -r '.name')
DEVOPS_SIGNER_PRIVATE_KEY=$(echo $signer_and_key | jq -r '.key')

source <(curl -s -S -L "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/image_signing/create_cise_crd.sh")
createCISE_CRD | tee cise_crd_custom_policy.yaml

echo " "
echo "Applying CISE custom policy to $CLUSTER_NAMESPACE"
kubectl apply -f cise_crd_custom_policy.yaml -n$CLUSTER_NAMESPACE

echo "Creating Secret $REGISTRY_NAMESPACE.$IMAGE_NAME.$DEVOPS_SIGNER to provide public key"
# ensure the secret is not already existing
kubectl delete secret "$REGISTRY_NAMESPACE.$IMAGE_NAME.$DEVOPS_SIGNER" -n$CLUSTER_NAMESPACE \
--ignore-not-found=true
kubectl create secret generic "$REGISTRY_NAMESPACE.$IMAGE_NAME.$DEVOPS_SIGNER" -n$CLUSTER_NAMESPACE \
--from-literal=name=$DEVOPS_SIGNER \
--from-file=publicKey=$DEVOPS_SIGNER.pub
done