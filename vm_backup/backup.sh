#!/bin/bash

MAIL_FROM=backup@nukularstrom.de
MAIL_TO=tyrant@nukularstrom.de
MAIL_VM=mail
LOG_FILE=/tmp/backup.log
GPG_RECIPIENT=tyrantcrp@gmail.com

SUCCESS=()
FAILED=()

function log {
  MSG=$*
  echo "$MSG"
  echo "$MSG" >> $LOG_FILE
}

function send_mail()
{
  local subject=$1
  local filename=$2
  IP_ADDR=$(sudo virsh domifaddr $MAIL_VM | tail -n 2 | head -n1 | tr -s ' ' | cut -d' ' -f5 | cut -d'/' -f1)
  heirloom-mailx -r "$MAIL_FROM" -s "[Backup] $subject" -S smtp="$IP_ADDR:587" -# -S smtp-use-starttls -S ssl-verify=ignore $MAIL_TO < "$filename"
}

function run_cmd()
{
  msg=$("$@" 2>&1)
  local status=$?
  if [ $status -ne 0 ]; then
      echo "$msg" >> $LOG_FILE
      echo "Command '$@' failed with $status" >> $LOG_FILE
  fi
  echo $msg
  return $status
}

function join_by { local d=$1; shift; echo -n "$1"; shift; printf "%s" "${@/#/$d}"; }

for VM in "$@"; do
  log "Backing up $VM ..."
  VIRSH_DOMIFADDR=$(sudo virsh domifaddr $VM 2>&1)

  if [ $? -ne 0 ]; then
    FAILED+=($VM)
    echo $VIRSH_DOMIFADDR >> $LOG_FILE
    continue
  fi

  IP_ADDR=$(echo "$VIRSH_DOMIFADDR" | tail -n 1 | tr -s ' ' | cut -d' ' -f5 | cut -d'/' -f1)
  FILENAME=$VM-$(date '+%Y.%m.%d_%H%M').tar.gz
  TARGET=/tmp/$FILENAME

  log "---------------------"
  OUTPUT=$(ssh root@$IP_ADDR /usr/share/backup/backup.sh $TARGET)
  log "$OUTPUT"
  log "---------------------"

  run_cmd scp root@$IP_ADDR:$TARGET .
  if [ $? -ne 0 ]; then
    FAILED+=($VM)
    continue
  fi

  run_cmd gpg --yes --batch --no-tty --recipient $GPG_RECIPIENT --encrypt $FILENAME
  if [ $? -ne 0 ]; then
    FAILED+=($VM)
    continue
  fi

  run_cmd aws s3 cp $FILENAME.gpg s3://skyrbackup/$VM/$FILENAME.gpg
  if [ $? -ne 0 ]; then
    FAILED+=($VM)
    continue
  fi

  rm $FILENAME.gpg
  rm $FILENAME

  log "Done!"
  log

  SUCCESS+=($VM)
done

SUBJECT=""
if [ ${#SUCCESS[@]} -ne 0 ]; then
  SUBJECT="Successful: $(join_by ', ' ${SUCCESS[@]})"
fi

if [ ${#FAILED[@]} -ne 0 ]; then
  SUBJECT+=" Failed: $(join_by ', ' ${FAILED[@]})"
fi


send_mail "$SUBJECT" "$LOG_FILE"
rm $LOG_FILE
