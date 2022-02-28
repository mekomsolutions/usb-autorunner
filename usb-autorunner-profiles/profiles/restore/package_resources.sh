#!/usr/bin/env bash

# Fail on first error:
set -e

PROFILE_DIR=$(dirname "$0")
BUILD_DIR=$PROFILE_DIR/target/build
BUILD_RESOURCES_DIR=$PROFILE_DIR/target/resources

# Utils
PACKAGING_UTILS_DIR=$PWD/resources/packaging_utils
RUN_UTILS_DIR=$PWD/resources/run_utils

DISTRO_VERSION=${DISTRO_VERSION}
ARTIFACT_GROUP=${ARTIFACT_GROUP:-net.mekomsolutions}

ARCHIVE_PATH=$PROFILE_DIR/archive
IMAGES_FILE=$BUILD_DIR/images.txt
K8S_VALUES_FILE=$BUILD_DIR/k8s-description-files/src/bahmni-helm/values.yaml
K8S_DEPLOYMENT_VALUES_FILE=$PROFILE_DIR/deployment-values.yml
: ${K8S_DESCRIPTION_FILES_GIT_REF:=master}
PVC_MOUNTER_IMAGE=mdlh/alpine-rsync:3.11-3.1-1

rm -rf $BUILD_DIR
mkdir -p $BUILD_DIR

rm -rf $BUILD_RESOURCES_DIR
mkdir -p $BUILD_RESOURCES_DIR

# Fetch distro
echo "⚙️ Download $DISTRO_NAME distro..."
mkdir -p $BUILD_DIR/distro
mvn org.apache.maven.plugins:maven-dependency-plugin:3.2.0:get -DremoteRepositories=https://nexus.mekomsolutions.net/repository/maven-public -Dartifact=$ARTIFACT_GROUP:bahmni-distro-$DISTRO_GROUP:$DISTRO_VERSION:zip -Dtransitive=false --legacy-local-repository
mvn org.apache.maven.plugins:maven-dependency-plugin:3.2.0:unpack -Dartifact=$ARTIFACT_GROUP:bahmni-distro-$DISTRO_GROUP:$DISTRO_VERSION:zip -DoutputDirectory=$BUILD_RESOURCES_DIR/distro

# Fetch K8s files
echo "⚙️ Clone K8s description files GitHub repo and checkout '$K8S_DESCRIPTION_FILES_GIT_REF'..."
rm -rf $BUILD_DIR/k8s-description-files
git clone https://github.com/mekomsolutions/k8s-description-files.git $BUILD_DIR/k8s-description-files
dir1=$PROFILE_DIR
dir2=$PWD
cd $BUILD_DIR/k8s-description-files && git checkout $K8S_DESCRIPTION_FILES_GIT_REF && cd $dir2

cat $K8S_DEPLOYMENT_VALUES_FILE
echo "⚙️ Run Helm to substitute custom values..."
helm template `[ -f $K8S_DEPLOYMENT_VALUES_FILE ] && echo "-f $K8S_DEPLOYMENT_VALUES_FILE"` $DISTRO_NAME $BUILD_DIR/k8s-description-files/src/bahmni-helm --output-dir $BUILD_DIR/k8s

# Get container images
cat /dev/null > $IMAGES_FILE
echo "⚙️ Add the $PVC_MOUNTER_IMAGE image"
echo "docker.io/$PVC_MOUNTER_IMAGE" >> $IMAGES_FILE

echo "⚙️ Parse the list of container images..."
grep -ri "image:" $BUILD_DIR/k8s/bahmni-helm/templates/apps/mysql $BUILD_DIR/k8s/bahmni-helm/templates/apps/postgresql | awk -F': ' '{print $3}' | xargs | tr " " "\n" >> $IMAGES_FILE
cat $K8S_VALUES_FILE | yq '.apps.backup_services.apps.mysql.image' -r >> $IMAGES_FILE
cat $K8S_VALUES_FILE | yq '.apps.backup_services.apps.postgres.image' -r >> $IMAGES_FILE
cat $K8S_VALUES_FILE | yq '.apps.backup_services.apps.filestore.image' -r >> $IMAGES_FILE

echo "⚙️ Read registry address from '$K8S_DEPLOYMENT_VALUES_FILE'"
registry_ip=$(grep -ri "docker_registry:" $K8S_DEPLOYMENT_VALUES_FILE | awk -F': ' '{print $2}' | tr -d " ")

temp_file=$(mktemp)
cp $IMAGES_FILE $temp_file
echo "⚙️ Override '$registry_ip' by 'docker.io'"
sed -e "s/${registry_ip}/docker.io/g" $IMAGES_FILE > $temp_file
echo "⚙️ Remove duplicates..."
sort $temp_file | uniq > $IMAGES_FILE
rm ${temp_file}
echo "ℹ️ Images to be downloaded:"
cat $IMAGES_FILE

echo "🚀 Download container images..."
set +e
mkdir -p $BUILD_RESOURCES_DIR/images
cat $IMAGES_FILE | $PACKAGING_UTILS_DIR/download-images.sh $BUILD_DIR/images
set -e

# Copy resources
mkdir -p $BUILD_RESOURCES_DIR/db_resources
echo "⚙️ Copy K8s description files..."
cp -r $BUILD_DIR/k8s/bahmni-helm/templates/common/* $BUILD_DIR/k8s/bahmni-helm/templates/configs/* $BUILD_DIR/k8s/bahmni-helm/templates/apps/mysql $BUILD_DIR/k8s/bahmni-helm/templates/apps/postgresql $BUILD_DIR/k8s/bahmni-helm/templates/apps/odoo/odoo-config.yml $BUILD_DIR/k8s/bahmni-helm/templates/apps/openmrs/openmrs-configs.yml $BUILD_DIR/k8s/bahmni-helm/templates/apps/openelis/openelis-config.yaml $BUILD_RESOURCES_DIR/db_resources
echo "⚙️ Copy 'run.sh' and 'utils/'..."
cp -R $PROFILE_DIR/run.sh $RUN_UTILS_DIR $BUILD_DIR/images $BUILD_RESOURCES_DIR/
echo "⚙️ Copy archive files..."
cp -R $ARCHIVE_PATH $BUILD_RESOURCES_DIR
