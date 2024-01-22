# Yake installation on AKS

There's a wide variety of managed kubernetes services. Here's a few of the big players you may have come across: Azure
Kubernetes Service (AKS), Google Kubernetes Engine (GKE), Amazon Elastic Kubernetes Service (Amazon EKS) and others.
All those kubernetes environments have subtle differences to them and installing YAKE may or may not require steps
specific to those enviroments.

This document will guide you through setting up YAKE on an AKS cluster. AKS being an arbitrary choice here, others are
up to the task just as well.

First of all clone the yake-install-examples repo and navigate to the azure directory:

```sh
git clone git@github.com:YAKEcloud/yake-install-examples.git
cd yake-install-examples/azure
```

You'll find this document and various .yaml and .yaml.example files in there. Copy the .example files to their .yaml
counterparts. You may notice various `# CHANGEME` comments in those files. We'll guide you through which values need to
be set and how to obtain them.

## Prerequisites

### Creating the cluster

Log into azure and [create a kubernetes cluster](https://portal.azure.com/#create/Microsoft.AKS). Name it `yake-cluster`
and place it in a new resource group named `yake-resource-group`

Make sure to select the "Kubenet" CNI since Azure's CNI doesn't meet gardener's requirements. All other default settings
should be fine but may change in the future.
At the time of writing (01/24) relevant default settings include:

- Network Policy: "Calico"
- Load balancer: "Standard"

### Creating a DNS zone

Log into azure and [create a DNS zone](https://portal.azure.com/#create/Microsoft.DnsZone-ARM).
Choose a domain or subdomain of your liking. Whenever this guide refers to this (sub)domain, `example.org` will be used.
Make sure to set this domain in config/yake-config.secret.yaml (.domains.global.domain)

### Creating credentials

There are two distinct interactions with azure that require valid credentials:

1. Management of DNS records
2. Management of shoots (i.e. clusters) which comprises management of various resources

The latter
requires [a vast amount of different permissions](https://gardener.cloud/docs/extensions/infrastructure-extensions/gardener-extension-provider-azure/azure-permissions/)
to succeed.
Instead of granting all of those we'll create a rather powerful entity for now: The subscription contributor. It's
authorized to create and manage any resource belonging to the respective subscription, so you might want to tighten
these permissions in a production setup.

To do so we need to:

1. Create an App Registration. Call it `yake`.
2. Go to your Subscription and add a Role Assignment assigning member `yake` with role `Contributor` (Role -> Privileged
   administrator roles)
3. Create a secret for your App Registration, make sure to copy the secret value!

The complete credentials passed to gardener consist of four parts:

```yaml 
subscriptionID: # Subscription -> ID
tenantID:       # App Registration `yake` -> Directory (tenant) ID
clientID:       # App Registration `yake` -> Application (client) ID
clientSecret:   # App Registration -> Certificate & Secrets -> Secret Value
```

Add these credentials to config/yake-config.secret.yaml (.domains.global.credentials)
Also add them to garden-content/azure.secret.yaml (.data)

### Obtaining the kubeconfig

Azure provides a handy [CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) that, amongst a variety of
other things can obtain a kubeconfig for you:

```sh
az login
az account set --subscription <your subscription id>
az aks get-credentials --resource-group yake-resource-group --name yake-cluster
```

Your KUBECONFIG environment variable should now be set to the correct kubeconfig.

## Installation

Create configuration secrets

```sh
kubectl apply -f ./config/
```

### Flux

Yake relies on [flux](https://github.com/fluxcd/flux2/) to perform git-based reconciliation.
Install flux on the cluster. YAKE comes with a pinned version of flux, so we'll use that one instead of installing via the flux cli.

```sh
YAKE_VERSION=v1.86.1-0
kubectl apply -f https://raw.githubusercontent.com/YAKEcloud/yake/$YAKE_VERSION/flux-system/gotk-components.yaml
```

To let flux know where to find yake's files, create a flux `GitRepository` resource pointing to yake's repository and version tag on
GitHub.

```sh
YAKE_VERSION=v1.86.1-0
flux create source git --url="https://github.com/yakecloud/yake.git" --tag=$YAKE_VERSION yake
```

Let's use the `yake` source in a flux `Kustomization` to make flux apply the kustomize `Kustomization`
/kustomization.yaml

```sh
cat <<EOF | kubectl apply -f -
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: yake
  namespace: flux-system
spec:
  interval: 10s
  sourceRef:
    kind: GitRepository
    name: yake
  path: ./
  prune: true
EOF
```

Flux will now start rolling out a bunch of helmreleases. You can watch this using a tool like `k9s`. You can also just
have a quick break as this will likely take about 15 minutes to finish.
Once all helmreleases are installed you should be able to reach the gardener dashboard on https://dashboard.example.org
and login with the email and password you set in config/identity-values.yaml

You'll now see that there's nothing to do in the dashboard because there's no project your user has access to.

### Projects and Secrets

Let's create a project via the so-called virtual garden, the actual gardener API. Conveniently it's also a kubernetes
API.
Fetch the virtual garden kubeconfig from the cluster:

```sh
kubectl get secret -n garden garden-kubeconfig-for-admin -o yaml -o go-template='{{.data.kubeconfig|base64decode}}' > /tmp/garden-kubeconfig
```

Then apply the yaml files in garden-content/

```sh
KUBECONFIG=/tmp/garden-kubeconfig kubectl apply -f ./garden-content/
```

You'll notice that not only a `Project` resource was created, but a `Secret` and a `SecretBinding`, too. The `Secret`
contains your azure credentials, while the `SecretBinding` allows it to be used from within the `Project`.

Switch back to your browser tab on https://dashboard.example.org and hit refresh. A project with the name
"myproject" should appear in the dropdown menu on the left hand side. Select it and go to "Secrets". The list should
contain a secret "my-azure-secret" which means we're good to go. Navigate to "Clusters" and hit the plus-button in the
upper-right corner to create your first cluster.
