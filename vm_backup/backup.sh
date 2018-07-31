#!/bin/bash -xe

MAIL_FROM=backup@nukularstrom.de
MAIL_TO=tyrant@nukularstrom.de
MAIL_VM=mail
LOG_FILE=/tmp/backup.log
GPG_RECIPIENT=tyrantcrp@gmail.com

rm $LOG_FILE

function log {
  MSG=$*
  echo "$MSG"
  echo "$MSG" >> $LOG_FILE
}

send_mail()
{
  local subject=$1
  local filename=$2
  IP_ADDR=$(sudo virsh domifaddr $MAIL_VM | tail -n 2 |head -n1 | tr -s ' ' | cut -d' ' -f5 | cut -d'/' -f1)
  heirloom-mailx -r "$MAIL_FROM" -s "[Backup] $subject" -S smtp="$IP_ADDR:587" -# -S smtp-use-starttls -S ssl-verify=ignore $MAIL_TO < "$filename"
}

for VM in "$@"; do
  log "Backing up $VM ..."
  IP_ADDR=$(sudo virsh domifaddr $VM | tail -n 2 |head -n1 | tr -s ' ' | cut -d' ' -f5 | cut -d'/' -f1)

  FILENAME=$VM-$(date '+%Y.%m.%d_%H%M').tar.gz
  TARGET=/tmp/$FILENAME

  log "---------------------"
  OUTPUT=$(ssh root@$IP_ADDR /usr/share/backup/backup.sh $TARGET)
  log "$OUTPUT"
  log "---------------------"
  scp root@$IP_ADDR:$TARGET .
  gpg --yes --batch --no-tty --recipient $GPG_RECIPIENT --encrypt $FILENAME
  gdrive upload $FILENAME.gpg

  rm $FILENAME.gpg
  rm $FILENAME

  log "Done!"
  log
done

send_mail "Successful" "$LOG_FILE"
