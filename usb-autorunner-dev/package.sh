#!/usr/bin/env bash
set -e

CONFIG_PATH=/etc/usb-autorunner
CERTIFICATES_PATH=${CERT_PATH:-$CONFIG_PATH/certificates}

PROFILE_PATH=${PROFILE_PATH:-/opt/usb-autorunner-dev/profiles/$1}
PROFILE_RESOURCES_DIR=$PROFILE_PATH/target/resources
PROJECT_DIR=$(pwd)
TARGET_DIR=$PROJECT_DIR/target
BUILD_DIR=$TARGET_DIR/build

rm -rf $TARGET_DIR
mkdir -p $TARGET_DIR

rm -rf $BUILD_DIR
mkdir -p $BUILD_DIR

if [[ ! -f $CERTIFICATES_PATH/public.pem ]] && [[ -z "$CERT_PATH"]]
then
    echo "Default certificates are missing, generating new certs..."
    gen_cert
fi

if [[ ! -f $CERTIFICATES_PATH/public.pem ]]
then
    echo "Certificate not available, exiting."
    exit
fi


echo "⚙️ Run 'package_resources.sh'..."
bash $PROFILE_PATH/package_resources.sh

echo "⚙️ Compress resources into 'autorun.zip' file..."
cd $PROFILE_RESOURCES_DIR/ && zip $BUILD_DIR/autorun.zip -r ./* && cd $PWD

echo "⚙️ Generate a random secret key..."
openssl rand -base64 32 > $BUILD_DIR/secret.key

echo "⚙️ Encrypt the random secret key..."
openssl rsautl -encrypt -oaep -pubin -inkey $CERTIFICATES_PATH/public.pem -in $BUILD_DIR/secret.key -out $TARGET_DIR/secret.key.enc

echo "🔐 Encrypt 'autorun.zip' file..."
openssl enc -aes-256-cbc -md sha256 -in $BUILD_DIR/autorun.zip -out $TARGET_DIR/autorun.zip.enc -pass file:$BUILD_DIR/secret.key

date_checksum=`date +"%d-%m-%y_%R" | md5sum`
final_filename=$1-${date_checksum:0:9}.zip
echo "🗜 Zip all in '$final_filename' file..."
cd $TARGET_DIR
zip ${final_filename} autorun.zip.enc secret.key.enc

echo "✅ USB Autorunner packagaging is done successfully."
echo ""
echo "ℹ️ File: $TARGET_DIR/$final_filename"
