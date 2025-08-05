#!/bin/bash

# PostgreSQL configuration variables
PG_DATA="/data/pg15"        # Adjust for your PostgreSQL version and data directory
PG_USER="postgres"                  # Replace with your PostgreSQL user
PG_HOST="localhost"                      # Change if needed
BACKUP_DIR="/backup/basebackup"            # Adjust the backup directory
LOGDIR="/backup/log"
DATE=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="pg_basebackup_$DATE"
HOSTNAME=$(hostname)
LOGFILE=$LOGDIR/${BACKUP_NAME}.log
EMAIL_LIST="xx.xxx.xxx@xxxx.com"
#email_content_file="/tmp/daily_postgresdb_backup_mail_body.txt"
MAIL_BODY_TEMP="/tmp/daily_postgresdb_backup_mail_body_temp.txt"
HOSTNAME=$(hostname)
IP=$(ip a | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1)
MAIL_SUBJECT="[PG Alert] $IP HOSTNAME: $HOSTNAME Database Base Backup Failed"

# Create backup directory if it does not exist
mkdir -p "$BACKUP_DIR"
printf  "============================================================\n">$MAIL_BODY_TEMP
printf  "🚨 WARNING: 'xxxxdb' Database Base Backup Job Failed 🚨\n" >>$MAIL_BODY_TEMP
printf  "%s\n" "📅 Detection time: $(date)" >>$MAIL_BODY_TEMP
printf  "\n">>$MAIL_BODY_TEMP
printf  "============================================================\n" >>$MAIL_BODY_TEMP
printf  "🔍 Log Details Of Job:\n" >>$MAIL_BODY_TEMP


# Perform the base backup using pg_basebackup
echo "Starting PostgreSQL backup...">$LOGFILE
pg_basebackup -U "$PG_USER" -h "$PG_HOST" -p 5466 -D "$BACKUP_DIR/$BACKUP_NAME" -P -Ft -z -R --wal-method=stream >>$LOGFILE 2>&1

if [ $? -ne 0 ]; then
    echo -e "\npg_basebackup failed!">>$LOGFILE
        cat $LOGFILE>>$MAIL_BODY_TEMP
        mv $MAIL_BODY_TEMP $LOGFILE
        mailx -s "$MAIL_SUBJECT" "$EMAIL_LIST" <$LOGFILE
    exit 1
else
    echo "Base backup completed successfully." >>$LOGFILE
        #send_alert "[Job Status]" "PG basebackup successfully on $HOSTNAME -- ${DATE}"
fi

# Optional: Copy additional WAL files (if needed)
WAL_DIR="$PG_DATA/pg_wal"
WAL_BACKUP_DIR="$BACKUP_DIR/$BACKUP_NAME/wal"

mkdir -p "$WAL_BACKUP_DIR"

# Find and copy the WAL files from the current WAL directory
echo "Copying WAL files..." >>$LOGFILE
cp "$WAL_DIR/"00000001* "$WAL_BACKUP_DIR" >>$LOGFILE 2>&1

if [ $? -ne 0 ]; then
    echo -e "\nWAL file copy failed!" >>$LOGFILE
        cat $LOGFILE>>$MAIL_BODY_TEMP
        mv $MAIL_BODY_TEMP $LOGFILE
        mailx -s "$MAIL_SUBJECT" "$EMAIL_LIST" <$LOGFILE
    exit 1
else
    echo "WAL files copied successfully." >>$LOGFILE
fi

# Optionally, compress the backup folder
tar -czf "$BACKUP_DIR/$BACKUP_NAME.tar.gz" -C "$BACKUP_DIR" "$BACKUP_NAME" >>$LOGFILE 2>&1

if [ $? -ne 0 ]; then
    echo -e "\nBackup compressure failed to $BACKUP_DIR/$BACKUP_NAME.tar.gz" >>$LOGFILE
        cat $LOGFILE>>$MAIL_BODY_TEMP
        mv $MAIL_BODY_TEMP $LOGFILE
        mailx -s "$MAIL_SUBJECT" "$EMAIL_LIST" <$LOGFILE
    exit 1
else
    echo "Backup compression successfully $BACKUP_DIR/$BACKUP_NAME.tar.gz" >>$LOGFILE
fi

# Clean up the uncompressed backup directory if necessary
echo "backup file name is $BACKUP_DIR/$BACKUP_NAME" >>$LOGFILE
rm -rf "$BACKUP_DIR/$BACKUP_NAME"
find "$BACKUP_DIR/" -type f -name "*tar.gz" -mtime +3 -exec rm {} \;

echo "Backup process completed successfully." >>$LOGFILE
