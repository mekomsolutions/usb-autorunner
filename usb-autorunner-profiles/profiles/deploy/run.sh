#!/usr/bin/env bash

PWD=$(dirname "$0")
DISTRO_NAME=c2c
REGISTRY_IP=${REGISTRY_IP:-10.0.90.99}
SSD_MOUNT_POINT=/mnt/disks/ssd1/
kubectl_bin="/usr/local/bin/k3s kubectl"
: "${NAMESPACE:=default}"
TIMEZONE="America/Port-au-Prince"

echo "⌚️ Set the server time zone to '$TIMEZONE'"
timedatectl set-timezone $TIMEZONE

echo "🗂  Initialize local storage folders."
# Create data volumes
mkdir -p $SSD_MOUNT_POINT/data/postgresql
mkdir -p $SSD_MOUNT_POINT/data/mysql
# Create entrypoint-db volume
mkdir -p $SSD_MOUNT_POINT/data/entrypoint-db
# Create backup folder
mkdir -p $SSD_MOUNT_POINT/backup
# Create logging folder
mkdir -p $SSD_MOUNT_POINT/logging

# Ensure registry directory exists
echo "⏱  Wait for the registry to be ready..."
mkdir -p $SSD_MOUNT_POINT/registry
POD_NAME=$($kubectl_bin get pod -l app=registry -o jsonpath="{.items[0].metadata.name}" -n $NAMESPACE)
$kubectl_bin wait --for=condition=ready --timeout 1800s pod $POD_NAME -n $NAMESPACE

# sync images to registry
echo "⚙️  Upload container images to the registry at $REGISTRY_IP..."
skopeo sync --scoped --dest-tls-verify=false --src dir --dest docker $PWD/images/docker.io $REGISTRY_IP

# Apply config
echo "⚙️  Apply K8s description files: config/ ..."
$kubectl_bin apply -f $PWD/k8s/bahmni-helm/templates/configs

echo "⚙️  Upload the distro..."
# Sending distro to volume
$PWD/utils/upload-files.sh $REGISTRY_IP/mdlh/alpine-rsync:3.11-3.1-1 $PWD/distro/ distro-pvc

echo "🧽 Delete the current 'openmrs' pod"
$kubectl_bin delete pods -l app=openmrs -n $NAMESPACE

echo "🧽 Delete the current 'odoo' pod"
$kubectl_bin delete pods -l app=odoo -n $NAMESPACE

echo "🧽 Delete the current 'openelis' pod"
$kubectl_bin delete pods -l app=openelis -n $NAMESPACE

# Apply K8s description files
echo "⚙️  Apply K8s description files: common/ ..."
$kubectl_bin apply -f $PWD/k8s/bahmni-helm/templates/common
echo "⚙️  Apply K8s description files: apps/ ..."
$kubectl_bin apply -f $PWD/k8s/bahmni-helm/templates/apps/ -R

echo "✅  Done."
