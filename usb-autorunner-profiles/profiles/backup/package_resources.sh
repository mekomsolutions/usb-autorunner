#!/usr/bin/env bash
set -e

PROFILE_DIR=$(dirname "$0")
BUILD_DIR=$PROFILE_DIR/target/build
BUILD_RESOURCES_DIR=$PROFILE_DIR/target/resources

# Utils
PACKAGING_UTILS_DIR=$PWD/resources/packaging_utils

IMAGES_FILE=$BUILD_DIR/images.txt

rm -rf $BUILD_DIR
mkdir -p $BUILD_DIR

rm -rf $BUILD_RESOURCES_DIR
mkdir -p $BUILD_RESOURCES_DIR

# Copy run.sh as a build resource
cp $PROFILE_DIR/run.sh $BUILD_DIR/

echo "⚙️ Parse the list of container images from the run.sh ..."
# Init temporary dir
temp_file=$(mktemp)
# Empty/create file to hold the list of images
cat /dev/null > $IMAGES_FILE
grep -rih "image:" $BUILD_DIR/run.sh | awk -F': ' '{print $2}' | xargs | tr " " "\n" >> $IMAGES_FILE
cp $IMAGES_FILE $temp_file
# Substitute ${REGISTRY_IP} by 'docker.io'
sed -e "s/\${REGISTRY_IP}/docker.io/g" $IMAGES_FILE > $temp_file

echo "⚙️ Remove duplicates..."
sort $temp_file | uniq > $IMAGES_FILE
rm ${temp_file}
echo "ℹ️ Images to be downloaded:"
cat $IMAGES_FILE

echo "🚀 Download container images..."
mkdir -p $BUILD_RESOURCES_DIR/images
cat $IMAGES_FILE | $PACKAGING_UTILS_DIR/download-images.sh $BUILD_DIR/images

# Copy resources
echo "⚙️ Copy files..."
cp -R $PROFILE_DIR/run.sh $BUILD_DIR/images $BUILD_RESOURCES_DIR/
