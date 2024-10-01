#!/bin/sh

echo "Setting up primary server 1"
k3sup install --host FIP0 \
--user ubuntu \
--cluster \
--local-path kubeconfig \
--context default \
--k3s-extra-args "--disable traefik"

echo "Fetching the server's node-token into memory"

export NODE_TOKEN=$(k3sup node-token --host FIP0 --user ubuntu)

echo "Setting up additional server: 2"
k3sup join \
--host FIP1 \
--server-host FIP0 \
--server \
--node-token "$NODE_TOKEN" \
--user ubuntu \
--k3s-extra-args "--disable traefik" &

echo "Setting up additional server: 3"
k3sup join \
--host FIP2 \
--server-host FIP0 \
--server \
--node-token "$NODE_TOKEN" \
--user ubuntu \
--k3s-extra-args "--disable traefik" &
