#!/bin/bash

# Settings
BACKUP_DISK_SIZE=100G
USE_AWS=0
AWS_USER=aws
AWS_VAULT_NAME=Reefer

USE_GDRIVE=1
GDRIVE_USER=gdrive

MAIL_FROM=backup@nukularstrom.de
MAIL_TO=tyrant@nukularstrom.de
SMTP_SERVER=192.168.100.106:587
MAIL_ON_SUCCESS=1
BACKUP_VM=( gitlab database )

send_mail()
{
  local subject=$1
  local message=$2

  echo "$message" | heirloom-mailx -r "$MAIL_FROM" -s "[Backup] $subject" -S smtp="$SMTP_SERVER" -S smtp-use-starttls -S ssl-verify=ignore $MAIL_TO
}

run_cmd_log()
{
  msg=$("$@")
  local status=$?
  echo "$msg" >> /tmp/backup.log
  if [ $status -ne 0 ]; then
      echo "Command '$@' failed with $status" >> /tmp/backup.log

      send_mail "Error" "$(cat /tmp/backup.log)"
      exit 1
  fi

  return $status
}

run_cmd()
{
  msg=$("$@")
  local status=$?
  if [ $status -ne 0 ]; then
      echo "$msg" >> /tmp/backup.log
      echo "Command '$@' failed with $status" >> /tmp/backup.log

      send_mail "Error" "$(cat /tmp/backup.log)"
      exit 1
  fi

  return $status
}

mount_lvm()
{
  local lv_name=$1
  local lv_path="/dev/vg0/lv_$lv_name"
  local lv_bck_name=lv_${lv_name}_bck
  local lv_bck_path=${lv_path}_bck

  # Create a snapshot and mount it
  run_cmd lvcreate -s -L$BACKUP_DISK_SIZE -n $lv_bck_name $lv_path
  run_cmd kpartx -a -s $lv_bck_path

  sleep 1
  local mount_dir=$(mktemp -d) 
  run_cmd mount /dev/${lv_name}-vg/root $mount_dir

  echo $mount_dir
  return 0
}

unmount_lvm()
{
  local lv_name=$1
  local lv_path="/dev/vg0/lv_$lv_name"
  local lv_bck_name=lv_${lv_name}_bck
  local lv_bck_path=${lv_path}_bck
  local mount_dir=$2

  run_cmd umount $mount_dir
  run_cmd rm -r $mount_dir

  # Clean Up
  sleep 1
  run_cmd dmsetup remove ${lv_name}--vg-root
  run_cmd dmsetup remove ${lv_name}--vg-swap_1

  sleep 1
  run_cmd kpartx -d $lv_bck_path
  run_cmd dmsetup remove vg0-${lv_bck_name}
  run_cmd dmsetup remove vg0-${lv_bck_name}-cow

  run_cmd lvremove -y $lv_bck_path
}

backup()
{
  local lv_name=$1
  local mount_dir=$2

  local timestamp=$(date +"%Y%m%d%H%M")
  local archive_name="${lv_name}-${timestamp}.tar.gz"

  run_cmd chroot $mount_dir ./usr/share/backup/backup.sh "/$archive_name"
  echo $archive_name >> /tmp/backup.log

  if [ $USE_AWS -eq 1 ]; then
    run_cmd_log su -c "aws glacier upload-archive --account-id - --vault-name '$AWS_VAULT_NAME' --archive-description '$archive_name' --body '$mount_dir/$archive_name'" $AWS_USER
  elif [ $USE_GDRIVE -eq 1 ]; then
    run_cmd_log su -c "gdrive upload '$mount_dir/$archive_name'" $GDRIVE_USER
  fi
}

echo "Backup starting ..." > /tmp/backup.log

for i in "${BACKUP_VM[@]}"
do
  echo "############# $i" >> /tmp/backup.log
  mount_dir=$(mount_lvm $i)
  if [ $? -ne 0 ]; then
    exit 1
  fi

  backup $i $mount_dir
  unmount_lvm $i $mount_dir
done

if [ $MAIL_ON_SUCCESS -eq 1 ]; then
  send_mail "Success" "$(cat /tmp/backup.log)"
fi
