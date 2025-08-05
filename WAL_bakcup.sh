#!/bin/bash
# Define source and backup directories
source ~/.bash_profile
DATE=$(date +"%Y%m%d_%H%M%S")
WAL_ARCHIVE_DIR="/log/archivelog"
BACKUP_DIR="/backup/wal_backup"
#WAL_BACKUP_DIR=$BACKUP_DIR/${DATE}
LOGDIR="/backup/log"
EMAIL_LIST="xxx.xx@xxxx.com"
LOGFILE=$LOGDIR/WAL_backup_${DATE}.log
TIMEOUT_SEC=30         # timeout for archive process
MAIL_BODY_TEMP="/tmp/daily_postgresdb_backup_mail_body_temp.txt"
HOSTNAME=$(hostname)
IP=$(ip a | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1)
MAIL_SUBJECT="[PG Alert] $IP HOSTNAME: $HOSTNAME Database WAL Backup Failed"

# Create backup directory if it does not exist
mkdir -p "$BACKUP_DIR"
printf  "============================================================\n">$MAIL_BODY_TEMP
printf  "🚨 WARNING: Database WAL Backup Job Failed 🚨\n" >>$MAIL_BODY_TEMP
printf  "%s\n" "📅 Detection time: $(date)" >>$MAIL_BODY_TEMP
printf  "\n">>$MAIL_BODY_TEMP
printf  "============================================================\n" >>$MAIL_BODY_TEMP
printf  "🔍 Log Details Of Job:\n" >>$MAIL_BODY_TEMP

# function: record log and date
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}
#  Switch WAL and get filename
log "==== begin swtiching and archiving WAL  ===="
psql -U postgres -c "CHECKPOINT;">/dev/null
NEW_WAL=$( psql -U postgres -tA -c "SELECT pg_walfile_name(pg_switch_wal());" | tr -dc '0-9A-Fa-f'|tr 'a-f' 'A-F')
#echo "WAL file is $NEW_WAL" >$LOGFILE
if [ -z "$NEW_WAL" ]; then
  log "Error: can't get filename of new WAL!"
  cat $LOGFILE>>$MAIL_BODY_TEMP
  mv $MAIL_BODY_TEMP $LOGFILE
  mailx -s "$MAIL_SUBJECT" "$EMAIL_LIST" <$LOGFILE
  exit 1
fi
log " WAL switched: $NEW_WAL"
# Wait for archive completed
log "Waiting for archive completed (timeout: ${TIMEOUT_SEC}seconds)..."
ATTEMPTS=0
ARCHIVED=false

while [ $ATTEMPTS -lt $TIMEOUT_SEC ]; do
  LAST_ARCHIVED=$(psql -U postgres -t -c "SELECT last_archived_wal FROM pg_stat_archiver;" | tr -d '[:space:]')
  if [[ "$LAST_ARCHIVED" == "$NEW_WAL" ]]; then
    ARCHIVED=true
    break
  fi
  sleep 1
  ((ATTEMPTS++))
done

# Archive result
if $ARCHIVED; then
  log "Succeed: WAL $NEW_WAL has been archived!"
else
  log "Warning: No WAL archived,check the database configuration!"
  cat $LOGFILE>>$MAIL_BODY_TEMP
  mv $MAIL_BODY_TEMP $LOGFILE
  mailx -s "$MAIL_SUBJECT" "$EMAIL_LIST" <$LOGFILE
fi

# check if the WAL file generated
ARCHIVE_PATH="$WAL_ARCHIVE_DIR/$NEW_WAL"
if [ -f "$ARCHIVE_PATH" ]; then
  log "Succeed: Archived WAL file $ARCHIVE_PATH exist"
else
  log "Error: Archived WAL file $ARCHIVE_PATH not found!"
  cat $LOGFILE>>$MAIL_BODY_TEMP
  mv $MAIL_BODY_TEMP $LOGFILE
  mailx -s "$MAIL_SUBJECT" "$EMAIL_LIST" <$LOGFILE
  exit 1
fi

log "==== Completed in swtiching and archiving ===="

# Move WAL files to backup directory
log " Begin backup WAL files from $WAL_ARCHIVE_DIR to $BACKUP_DIR ..."
rsync -vzrtopg --progress $WAL_ARCHIVE_DIR/* $BACKUP_DIR/ >>$LOGFILE 2>&1
if [ $? -ne 0 ]; then
    log "WAL file backup failed!"
        cat $LOGFILE>>$MAIL_BODY_TEMP
        mv $MAIL_BODY_TEMP $LOGFILE
        mailx -s "$MAIL_SUBJECT" "$EMAIL_LIST" <$LOGFILE
    exit 1
else
    log "WAL files backup successfully."
#       send_alert "[Job Status]" "PG WAL files backup successfully on $HOSTNAME -- ${DATE}"
fi
find $WAL_ARCHIVE_DIR -type f -name "00000001*" -mtime +1 -exec rm {} \;


cd $BACKUP_DIR
# Optional: Delete WAL files older than a certain period (e.g., 7 days)
find $BACKUP_DIR -type f -name "00000001*" -mtime +7 -exec rm {} \;
find $LOGDIR -type f -name "*.log" -mtime +30 -exec rm {} \;
log "WAL files have been backed up."
exit 0
