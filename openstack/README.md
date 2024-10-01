# YAKE installation on Openstack with k3s

This document will guide you through setting up YAKE on k3s on OpenSstack.

First of all clone the yake-install-examples repo and navigate to the openstack directory:

```sh
git clone git@github.com:YAKEcloud/yake-install-examples.git
cd yake-install-examples/openstack
```

You'll find this document and various .yaml and .yaml.example files in there. Copy the .example files to their .yaml counterparts. You may notice various `# CHANGEME` comments in those files. We'll guide you through which values need to be set and how to obtain them.

## Prerequisites

### Creating the cluster

Create 3 or more nodes on your Openstack cluster. You can do this with Terraform (OpenTofu), for example.

An example of how to do this with Terraform can be found in the `terraform` folder.

Once the nodes are in place, k3s can be installed. We use the k3sup for this: https://github.com/alexellis/k3sup. The `/k3sup` folder contains two sample files that can be used for the cluster. The `FIPs` must be exchanged for the real IPs from the terraform setup (https://github.com/alexellis/k3sup?tab=readme-ov-file#k3sup-plan-for-automation).

### Creating a DNS zone

A DNS zone can be created via Deisgnate, for example. Only the zone needs to be created there.

### Creating credentials

The credentials do not have to be created separately. All credentials are contained in `clouds.yaml` and can be copied from there.

The complete credentials passed to gardener consist of seven parts:

```yaml
OS_AUTH_URL: # CHANGEME
OS_REGION_NAME: # CHANGEME
OS_DOMAIN_NAME: # CHANGEME
OS_USERNAME: # CHANGEME
OS_PASSWORD: # CHANGEME
OS_PROJECT_NAME: # CHANGEME
OS_USER_DOMAIN_NAME: # CHANGEME
```

Add these credentials to config/yake-config.secret.yaml (.domains.global.credentials)
Also add them to garden-content/openstack.secret.yaml (.data)

### Obtaining the kubeconfig

`k3sup` automatically saves the `kubeconfig` in the folder where you are currently located or where you execute the command to build the cluster.

## Installation

Create configuration secrets

```sh
kubectl apply -f ./config/
```

### Flux

YAKE relies on [flux](https://github.com/fluxcd/flux2/) to perform git-based reconciliation.
Install flux on the cluster. YAKE comes with a pinned version of flux, so we'll use that one instead of installing via the flux cli.

```sh
YAKE_VERSION=v1.103.0-1
kubectl apply -f https://raw.githubusercontent.com/YAKEcloud/yake/$YAKE_VERSION/flux-system/gotk-components.yaml
```

To let flux know where to find YAKE's files, create a flux `GitRepository` resource pointing to YAKE's repository and version tag on GitHub.

```sh
YAKE_VERSION=v1.103.0-1
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

Flux will now start rolling out a bunch of helmreleases. You can watch this using a tool like `k9s`. You can also just have a quick break as this will likely take about 15 minutes to finish.
Once all helmreleases are installed you should be able to reach the gardener dashboard on https://dashboard.example.org and login with the email and password you set in config/identity-values.yaml

You'll now see that there's nothing to do in the dashboard because there's no project your user has access to.

### Projects and Secrets

Let's create a project via the so-called virtual garden, the actual gardener API. Conveniently it's also a kubernetes API. Fetch the virtual garden kubeconfig from the cluster:

```sh
kubectl get secret -n garden garden-kubeconfig-for-admin -o yaml -o go-template='{{.data.kubeconfig|base64decode}}' > /tmp/garden-kubeconfig
```

Then apply the yaml files in garden-content/

```sh
KUBECONFIG=/tmp/garden-kubeconfig kubectl apply -f ./garden-content/
```

You'll notice that not only a `Project` resource was created, but a `Secret` and a `SecretBinding`, too. The `Secret` contains your azure credentials, while the `SecretBinding` allows it to be used from within the `Project`.

Switch back to your browser tab on https://dashboard.example.org and hit refresh. A project with the name "myproject" should appear in the dropdown menu on the left hand side. Select it and go to "Secrets". The list should contain a secret "my-azure-secret" which means we're good to go. Navigate to "Clusters" and hit the plus-button in the upper-right corner to create your first cluster.
