#!/bin/bash

# ----------------------
# volume が作られた状態で失敗した場合の volume の消し方:
#   sudo docker volume rm <Volume Name>
# (削除確認)
#   sudo ls -al /var/lib/docker/volumes
# ----------------------


# 環境変数の読み込み
. .backup-tool.env

# 元のディレクトリを保存
ORIGINAL_DIR=$(pwd)
# ツールのディレクトリ
TOOL_DIR=$(cd $(dirname $0) && pwd)

# ターゲットディレクトリに移動
cd "$BKUP_WORK_DIR" || { echo "Target directory $BKUP_WORK_DIR not found. Exiting."; exit 1; }

# リストア関数
restore_volume() {
  VOLUME_NAME=$1
  RESTORE_SOURCE=$2
  VOLUME_PATH="/var/lib/docker/volumes/${BKUP_PREFIX}${VOLUME_NAME}"
  
  echo "Executing: docker volume create ${BKUP_PREFIX}${VOLUME_NAME}"
  docker volume inspect "${BKUP_PREFIX}${VOLUME_NAME}" >/dev/null 2>&1
  # docker volume inspect "${BKUP_PREFIX}${VOLUME_NAME}"
  # echo "kekka:" $?
  if [ $? -eq 0 ]; then
    echo "Volume ${BKUP_PREFIX}${VOLUME_NAME} already exists. Exiting."
    exit 1
  fi
  
  docker volume create "${BKUP_PREFIX}${VOLUME_NAME}"
  sudo tar -xzf "$TOOL_DIR/data/$RESTORE_SOURCE" -C "$VOLUME_PATH" --preserve-permissions --numeric-owner
}

restore_file_or_dir() {
  RESTORE_SOURCE=$1
  DEST_PATH=$2
  
  echo "Executing: sudo tar -xzf \"$RESTORE_SOURCE\" -C \"$(dirname \"$DEST_PATH\")\" --preserve-permissions --numeric-owner"
  sudo tar -xzf "$TOOL_DIR/data/$RESTORE_SOURCE" -C "$(dirname "$DEST_PATH")" --preserve-permissions --numeric-owner
}

# ボリュームのリストア
IFS=',' read -ra VOLUMES <<< "$BKUP_VOLUMES"
for VOLUME in "${VOLUMES[@]}"; do
  restore_volume "$VOLUME" "${VOLUME}_backup.tar.gz"
done

# 任意のファイル・フォルダのリストア
IFS=',' read -ra FILES <<< "$BKUP_FILES"
for FILE in "${FILES[@]}"; do
  BACKUP_NAME=$(basename "$FILE")
  restore_file_or_dir "${BACKUP_NAME}_backup.tar.gz" "$FILE"
done

# 元のディレクトリに戻る
cd "$ORIGINAL_DIR"
