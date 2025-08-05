#!/bin/bash
# Define source and backup directories
source ~/.bash_profile
DATE=$(date +"%Y%m%d_%H%M%S")
BASE_BACKUP_DIR="/backup/basebackup"
WAL_BACKUP_DIR="/backup/wal_backup"
NFS_FOLDER="/bak_data"
#WAL_BACKUP_DIR=$BACKUP_DIR/${DATE}
LOGDIR="/backup/log"
EMAIL_LIST="xxx.xx@xxxxx.com"
LOGFILE=$LOGDIR/pg_transfer_nfs_${DATE}.log
TARGET_BASE_DIR="$NFS_FOLDER/$HOSTNAME/basebackup"
TARGET_WAL_DIR="$NFS_FOLDER/$HOSTNAME/wal_backup"
MAIL_BODY_TEMP="/tmp/daily_postgresdb_backup_mail_body_temp.txt"
HOSTNAME=$(hostname)
IP=$(ip a | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1)
MAIL_SUBJECT="[PG Alert] $IP HOSTNAME: $HOSTNAME Database Backup Files Transfer To NFS Failed"

# function: record log and date
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

printf  "============================================================\n">$MAIL_BODY_TEMP
printf  "🚨 WARNING: Database Backup Files Transfer to NFS Failed 🚨\n" >>$MAIL_BODY_TEMP
printf  "%s\n" "📅 Detection time: $(date)" >>$MAIL_BODY_TEMP
printf  "\n">>$MAIL_BODY_TEMP
printf  "============================================================\n" >>$MAIL_BODY_TEMP
printf  "🔍 Log Details Of Job:\n" >>$MAIL_BODY_TEMP

if ! mountpoint -q $NFS_FOLDER; then
  log "[ERROR]NFS Folder $NFS_FOLDER not mounted！"
  exit 1
fi

# 目录预检查（存在性 + 可写性）
precheck_directory() {
  local dir_type=$1   # 目录类型标识（用于日志）
  local target_dir=$2

  # 存在性检查
  if [ ! -d "$target_dir" ]; then
    log "[WARN][$(date +%T)] $dir_type folder not exists，tring to make: $target_dir"
    mkdir -p "$target_dir" || {
      log "[ERROR]Failed to create folder: $target_dir"
          cat $LOGFILE>>$MAIL_BODY_TEMP
          mv $MAIL_BODY_TEMP $LOGFILE
          mailx -s "$MAIL_SUBJECT" "$EMAIL_LIST" <$LOGFILE
          exit 1
      return 1
    }
  fi

  # 可写性验证
  local test_file="$target_dir/.write_test_$(date +%s)"
  touch $test_file 2>/dev/null && rm -f $test_file || {
    log "[ERROR]$dir_type is not writable: $target_dir"
        cat $LOGFILE>>$MAIL_BODY_TEMP
        mv $MAIL_BODY_TEMP $LOGFILE
        mailx -s "$MAIL_SUBJECT" "$EMAIL_LIST" <$LOGFILE
        exit 1
    return 1
  }
  log "[CHECK]$dir_type verification passed: $target_dir"
  return 0
}

sync_with_retry() {
  local src=$1
  local dest=$2

  echo "----- sync $src → $dest -----" >> $LOGFILE
  rsync -rlptDvzhu --progress --delete --partial --exclude="*.tmp" $src/ $dest/ >> $LOGFILE 2>&1

  if [ $? -ne 0 ]; then
    log "[ERROR]$src sync failed"
        cat $LOGFILE>>$MAIL_BODY_TEMP
        mv $MAIL_BODY_TEMP $LOGFILE
        mailx -s "$MAIL_SUBJECT" "$EMAIL_LIST" <$LOGFILE
        exit 1
    return 1
  else
    log "[SUCCESS]$src sync completed"
    return 0
  fi
}

# ----------------- 主流程 -----------------
error_flag=0

# 预检查阶段
precheck_directory "Basebackup_Folder" $TARGET_BASE_DIR || error_flag=1
precheck_directory "WAL_Folder" $TARGET_WAL_DIR || error_flag=1

# 如果预检查失败直接退出
if [ $error_flag -ne 0 ]; then
  log "[Job Status]" "Failed on checking NFS Folders on $HOSTNAME"
  cat $LOGFILE>>$MAIL_BODY_TEMP
  mv $MAIL_BODY_TEMP $LOGFILE
  mailx -s "$MAIL_SUBJECT" "$EMAIL_LIST" <$LOGFILE
  exit 1
fi

# 执行同步
sync_with_retry $BASE_BACKUP_DIR $TARGET_BASE_DIR || error_flag=1
sync_with_retry $WAL_BACKUP_DIR $TARGET_WAL_DIR || error_flag=1

# 最终处理
if [ $error_flag -ne 0 ]; then
  log "[Job Status]" "PG backup files failed to transfer to NFS on $HOSTNAME"
  cat $LOGFILE>>$MAIL_BODY_TEMP
  mv $MAIL_BODY_TEMP $LOGFILE
  mailx -s "$MAIL_SUBJECT" "$EMAIL_LIST" <$LOGFILE
  exit 1
else
  log "[INFO]All backup files transferred to $NFS_FOLDER/$HOSTNAME"
#  send_alert "[Job Status]" "PG backup files succeed in transferring to NFS on $HOSTNAME - ${DATE}"
  exit 0
fi
