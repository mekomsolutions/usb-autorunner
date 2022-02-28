#!/usr/bin/env bash
installation_folder=/opt/usb-autorunner
config_folder=/etc/usb-autorunner

TEMP_PATH=/tmp/autorunner/
AUTORUNNER_WORKDIR=$installation_folder/workdir
PRIVATE_CERT=$config_folder/certificates/private.pem
PUBLIC_CERT=$config_folder/certificates/public.pem
USB_INFO_FILE=$config_folder/usbinfo

AUTORUN_FILENAME=autorun.zip.enc
SECRET_KEY_FILENAME=secret.key.enc

MOUNT_POINT=$1

if [ ! -r $MOUNT_POINT/$SECRET_KEY_FILENAME ]
then
  echo "Secret key file '$SECRET_KEY_FILENAME' is missing at path $MOUNT_POINT/"
  exit 1
fi

if [ -r $MOUNT_POINT/$AUTORUN_FILENAME ]
then
  # Write USB information
  echo "mount_point=$MOUNT_POINT" > $USB_INFO_FILE

  autorun_file_path=$(find $MOUNT_POINT -maxdepth 1 -name $AUTORUN_FILENAME)
  decrypt_key_path=$(find $MOUNT_POINT -maxdepth 1 -name $SECRET_KEY_FILENAME)

  # Clean workdir
  echo "🧽 Clean working directory..."
  rm -rf $AUTORUNNER_WORKDIR/*
  rm -rf $TEMP_PATH
  mkdir -p $TEMP_PATH

  # Decrypting and executing the autorun script
  echo "🔓 Decrypt 'secret.key'..."
  openssl rsautl -decrypt -oaep -inkey $PRIVATE_CERT -in $decrypt_key_path -out $TEMP_PATH/secret.key
  echo "🔓 Decrypt 'autorun.zip'..."
  openssl enc -d -aes-256-cbc -md sha256 -in $autorun_file_path -out $TEMP_PATH/autorun.zip -pass file:$TEMP_PATH/secret.key
  echo "⚙️  Unzip 'autorun.zip'..."
  unzip -oq $TEMP_PATH/autorun.zip -d $AUTORUNNER_WORKDIR

  if [ -r $AUTORUNNER_WORKDIR/run.sh ]
  then
    echo "🚀 Run 'run.sh'..."
    bash $AUTORUNNER_WORKDIR/run.sh
  else
    echo "⚠️ run.sh file is not found in the extracted zip archive. Abort."
    exit 1
  fi
else
  echo "⚠️ No autorun defined, exiting"
  exit 1
fi
