#!/bin/bash

# -------------------------------------------------------
# 前提
# ・ sshpass コマンドをインストールしていること
# ・ visudo で 下記を追記し、 sudo tar 実行によりパスワードを求められないようにすること
#   `<ユーザー名> ALL=(ALL:ALL) NOPASSWD: /bin/tar`
# -------------------------------------------------------

# 環境変数の読み込み
. ./.backup-tool.env

# 元のディレクトリを保存
ORIGINAL_DIR=$(pwd)
# ツールのディレクトリ
TOOL_DIR=$(cd $(dirname $0) && pwd)
# ログ
LOG_FILE="${TOOL_DIR}/backup.log"


echo "----------------------------------------------------------------------------------------------" | tee -a ${LOG_FILE}
echo "Datetime: $(date)" | tee -a ${LOG_FILE}
echo "----------------------------------------------------------------------------------------------" | tee -a ${LOG_FILE}

# バックアップ関数
backup_volume() {
  VOLUME_NAME=$1
  BACKUP_DESTINATION=$2
  echo "Backing up volume ${BKUP_PREFIX}${VOLUME_NAME} to ${BACKUP_DESTINATION}" | tee -a ${LOG_FILE}
  echo ${BKUP_USER_PW} | sudo -S tar --warning=no-file-changed -czf "$BACKUP_DESTINATION" -C "/var/lib/docker/volumes/${BKUP_PREFIX}${VOLUME_NAME}" _data 2>&1 | tee -a ${LOG_FILE}
}

backup_file_or_dir() {
  SOURCE_PATH=$1
  BACKUP_DESTINATION=$2
  echo "Backing up file or directory $SOURCE_PATH to $BACKUP_DESTINATION" | tee -a ${LOG_FILE}
  echo ${BKUP_USER_PW} | sudo -S tar -czf "$BACKUP_DESTINATION" -C "$(dirname "$SOURCE_PATH")" "$(basename "$SOURCE_PATH")" 2>&1 | tee -a ${LOG_FILE}
}


# ターゲットディレクトリに移動
cd "$BKUP_WORK_DIR" || { echo "Target directory $BKUP_WORK_DIR not found. Exiting." | tee -a ${LOG_FILE}; exit 1; }

# ボリュームのバックアップ
VOLUMES=$(echo $BKUP_VOLUMES | tr ',' ' ')
for VOLUME in $VOLUMES; do
  backup_volume "$VOLUME" "${TOOL_DIR}/data/${VOLUME}_backup.tar.gz"
done

# 任意のファイル・フォルダのバックアップ
FILES=$(echo $BKUP_FILES | tr ',' ' ')
for FILE in $FILES; do
  BACKUP_NAME=$(basename "$FILE")
  backup_file_or_dir "$FILE" "${TOOL_DIR}/data/${BACKUP_NAME}_backup.tar.gz"
done

# 日時フォルダの作成
TIMESTAMP=$(date +"%Y%m%d%H%M")
REMOTE_DIR="${BKUP_TARGET_DIR}/${TIMESTAMP}"

# ディレクトリの作成
echo "Creating directory on remote host..." | tee -a ${LOG_FILE}
# sshpass -p "$BKUP_TARGET_PASSWD" ssh "$BKUP_TARGET_USER@$BKUP_TARGET_HOST" "mkdir -p $REMOTE_DIR"
sshpass -p "$BKUP_TARGET_PASSWD" ssh -o StrictHostKeyChecking=no "$BKUP_TARGET_USER@$BKUP_TARGET_HOST" "mkdir -p $REMOTE_DIR" 2>&1
if [ $? -ne 0 ]; then
  echo "Failed to create directory $REMOTE_DIR on remote host $BKUP_TARGET_HOST" | tee -a ${LOG_FILE}
  exit 1
else
  echo "Successfully created directory $REMOTE_DIR on remote host $BKUP_TARGET_HOST" | tee -a ${LOG_FILE}
fi

# バックアップファイルのリモートサーバへの転送
transfer_success=true
# バックアップファイルの転送
find ${TOOL_DIR}/data -name '*_backup.tar.gz' | while read -r BACKUP_FILE; do
  echo "Transferring $BACKUP_FILE to $BKUP_TARGET_HOST ..." | tee -a ${LOG_FILE}
  sshpass -p "$BKUP_TARGET_PASSWD" scp "$BACKUP_FILE" "$BKUP_TARGET_USER@$BKUP_TARGET_HOST:$REMOTE_DIR"
  if [ $? -eq 0 ]; then
    echo "Successfully transferred $BACKUP_FILE to $BKUP_TARGET_HOST" | tee -a ${LOG_FILE}
  else
    echo "Failed to transfer $BACKUP_FILE to $BKUP_TARGET_HOST" | tee -a ${LOG_FILE}
    transfer_success=false
  fi
done

# 古いバックアップのローテーション処理
if [ "$transfer_success" = true ]; then
  echo "Creating rotation script on local host..." | tee -a ${LOG_FILE}
  cat << EOF > rotation_script.sh
#!/bin/bash
cd "$BKUP_TARGET_DIR"
if [ \$(ls -1 "$BKUP_TARGET_DIR" | wc -l) -gt 3 ]; then
  echo "Performing backup rotation..."
  ls -1t "$BKUP_TARGET_DIR" | tail -n +4 | xargs -I {} rm -rf {}
  echo "Each backup size:"
  du -h "${BKUP_TARGET_DIR}" 2>&1
else
  echo "No need for backup rotation."
fi
EOF

  echo "Transferring rotation script to remote host..." | tee -a ${LOG_FILE}
  sshpass -p "$BKUP_TARGET_PASSWD" scp rotation_script.sh "$BKUP_TARGET_USER@$BKUP_TARGET_HOST:$REMOTE_DIR"
  if [ $? -eq 0 ]; then
    echo "Successfully transferred rotation script to $BKUP_TARGET_HOST" | tee -a ${LOG_FILE}
    echo "Executing rotation script on remote host..." | tee -a ${LOG_FILE}
    sshpass -p "$BKUP_TARGET_PASSWD" ssh "$BKUP_TARGET_USER@$BKUP_TARGET_HOST" "bash $REMOTE_DIR/rotation_script.sh" | tee -a ${LOG_FILE}
    echo "Deleting rotation script from remote host..." | tee -a ${LOG_FILE}
    sshpass -p "$BKUP_TARGET_PASSWD" ssh "$BKUP_TARGET_USER@$BKUP_TARGET_HOST" "rm $REMOTE_DIR/rotation_script.sh"
  else
    echo "Failed to transfer rotation script to $BKUP_TARGET_HOST" | tee -a ${LOG_FILE}
  fi
fi

# ローカルのバックアップファイルを削除
rm -f ${TOOL_DIR}/data/*_backup.tar.gz

echo  | tee -a ${LOG_FILE}

# 元のディレクトリに戻る
cd "$ORIGINAL_DIR"