#!/bin/bash

if [ $# -lt 2 ]; then
  echo "Usage: $0 <vm_name> <target>"
  exit 1
fi

# Settings
USER=gdrive

# Internal variables
VM=$1
TARGET=$2

if [ "$3" != "" ]; then
  DAYS_AGO=$3
else
  DAYS_AGO=1
fi

FILE=$(aws s3api list-objects --bucket skyrbackup --prefix "$VM" --query 'reverse(sort_by(Contents,&LastModified))[*].[Key]' --output text | sed "${DAYS_AGO}d;q" -)
echo $FILE
aws s3 cp s3://skyrbackup/$FILE $VM.tar.gz.gpg
gpg --decrypt --yes --batch --no-tty $VM.tar.gz.gpg > $TARGET/$VM.tar.gz
rm $VM.tar.gz.gpg
