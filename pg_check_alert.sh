#!/bin/bash

# PostgreSQL日志文件路径
DAYOFWEEK=$(date +%a)
PG_LOG_FILE="/data/pgsql/17/data/log/postgresql-$DAYOFWEEK.log"  # 根据您的设置修改路径
# 邮件收件人
EMAIL_LIST="xx.xxx@xxxx.com"
# 临时文件用于存放上次检查的位置
LAST_POS_FILE="/tmp/pg_log_last_pos"

# 检查并创建临时文件
if [[ ! -f $LAST_POS_FILE ]]; then
  echo "0" > $LAST_POS_FILE
fi

# 读取上次检查的位置
LAST_POS=$(cat $LAST_POS_FILE)

# 监控日志文件，查找“ERROR”关键字
# 使用tail命令来获取日志文件的新内容
NEW_ERRORS=$(tail -n +$((LAST_POS + 1)) "$PG_LOG_FILE" | grep "ERROR")

# 如果找到了新的错误
if [[ ! -z $NEW_ERRORS ]]; then
  # 发送告警邮件
  echo "P1 issue" | mailx "Subject: PostgreSQL Error Alert-new error message:\n$NEW_ERRORS" "$EMAIL_LIST"
fi

# 更新最后检查的位置
NEW_LAST_POS=$(wc -l < "$PG_LOG_FILE")
echo "$NEW_LAST_POS" > $LAST_POS_FILE
[postgres@sg-dba-inventorydbinfraappsrv01 ~]$ cat pg_check_alert_new.sh
#!/bin/bash

# ==============================================
# 配置区域（根据实际环境调整）
# ==============================================
PG_LOG_DIR="/data/pgsql/17/data/log"
DAYOFWEEK=$(date +%a)
PG_LOG_FILE="${PG_LOG_DIR}/postgresql-${DAYOFWEEK}.log"
ALERT_KEYWORDS="ERROR|WARNING|FATAL"
#EMAIL_LIST="apac.dba.sql@dbschenker.com"
EMAIL_LIST="Robert.shi@dbschenker.com"
HOSTNAME=$(hostname)
IP=$(ip a | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1)
MAIL_SUBJECT="[PG Alert] $IP HOSTNAME: $HOSTNAME Database Warning/Error Detected"

# ==============================================
# 临时文件定义（无需修改）
# ==============================================
LAST_POS_FILE="/tmp/pg_log_last_pos"
ALERT_CONTENT_FILE="/tmp/pg_log_alert_content"
ALERT_HASH_FILE="/tmp/pg_alert_hash.tmp"
ALERT_MAIL_BODY="/tmp/pg_alert_mail_body"
ALERT_MAIL_BODY_TEMP="/tmp/pg_alert_mail_body_temp"
MAX_LOG_AGE_SECONDS=3600

# ==============================================
# 初始化检查
# ==============================================
[ -d "$PG_LOG_DIR" ] || { echo "日志目录不存在: $PG_LOG_DIR"; exit 1; }
[ -f "$PG_LOG_FILE" ] || { echo "日志文件不存在: $PG_LOG_FILE"; exit 1; }

# 初始化位置记录文件
if [[ ! -f $LAST_POS_FILE ]]; then
    touch $LAST_POS_FILE
    for day in Mon Tue Wed Thu Fri Sat Sun; do
        echo "$day:0" >> $LAST_POS_FILE
    done
fi

# 生成过去6天的星期名称
reset_days=($(for i in {1..6}; do date -d "-$i day" +%a; done))

# 使用awk一次性重置这些天数的位置为0
awk -i inplace -F':' -v days="${reset_days[*]}" -v today="$DAYOFWEEK" -v new_pos=0 '
BEGIN {
  split(days, day_arr, " ")
  for (i in day_arr) {
    target_days[day_arr[i]]
  }
}
{
  if ($1 in target_days && $1 != today) {
    $2 = new_pos
  }
  print $0
}' OFS=':' "$LAST_POS_FILE"
# ==============================================
# 主处理流程
# ==============================================
    # 清空临时文件
    : > "$ALERT_CONTENT_FILE"
    : > "$ALERT_MAIL_BODY"

    # 获取上次检查位置
    LAST_POS=$(awk -F':' -v day="$DAYOFWEEK" '$1 == day {print $2}' "$LAST_POS_FILE")

    # 实时监控新日志（10秒超时）
    timeout 10 tail -n +$((LAST_POS + 1)) --pid=$$ -F "$PG_LOG_FILE" |
    while read -t 5 line; do
        # 关键字匹配
        if echo "$line" | grep -qE "$ALERT_KEYWORDS"; then
            # 生成内容哈希
            log_hash=$(echo -n "$line" | md5sum | cut -d' ' -f1)

            # 去重检查
            if ! grep -q "$log_hash" "$ALERT_HASH_FILE"; then
                # 记录哈希及时间戳
                echo "$log_hash $(date +%s)" >> "$ALERT_HASH_FILE"
                printf "$line\n" >> "$ALERT_MAIL_BODY"
            fi
        fi
    done

    # 仅在存在告警内容时发送邮件
    if [[ -s "$ALERT_MAIL_BODY" ]]; then
        echo "New Error/Warning detected, send the email.."
        printf "============================================================\n" > "$ALERT_MAIL_BODY_TEMP"
        printf "🚨 WARNING: PostgreSQL Error/Warning Log Detected 🚨\n" >> "$ALERT_MAIL_BODY_TEMP"
        printf "%s\n" "📅 Detection time: $(date)"  >> "$ALERT_MAIL_BODY_TEMP"
        printf "\n">> "$ALERT_MAIL_BODY_TEMP"
        printf "============================================================\n" >> "$ALERT_MAIL_BODY_TEMP"
        printf "🔍 Error/Warning Log Details:\n" >> "$ALERT_MAIL_BODY_TEMP"
        cat $ALERT_MAIL_BODY>>$ALERT_MAIL_BODY_TEMP
        mv $ALERT_MAIL_BODY_TEMP $ALERT_MAIL_BODY
        mailx -s "$MAIL_SUBJECT" "$EMAIL_LIST" < "$ALERT_MAIL_BODY"
    else
        echo "No new Error/Warning found."
    fi

    # 更新最后读取位置
    NEW_LAST_POS=$(wc -l < "$PG_LOG_FILE")
    awk -i inplace -F':' -v day="$DAYOFWEEK" -v pos="$NEW_LAST_POS" \
        '$1==day {$2=pos} {print}' OFS=":" "$LAST_POS_FILE"

    # 清理过期哈希（1小时前记录）
    awk -v now=$(date +%s) -v max_age="$MAX_LOG_AGE_SECONDS" \
        'now - $2 > max_age {print $1}' "$ALERT_HASH_FILE" | \
    while read -r hash; do
        sed -i "/^$hash/d" "$ALERT_HASH_FILE"
    done
