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

FILE_ID=$(su -c "gdrive list --no-header --order \"createdTime\" -q \"trashed = false and 'me' in owners and name contains '$VM'\" | sed '${DAYS_AGO}d;q' - | cut -d' ' -f1" $USER)
su -c "gdrive download --path /tmp/$VM.tar.gz.gpg $FILE_ID" $USER
gpg --decrypt --yes --batch --no-tty > $TARGET/$VM.tar.gz
