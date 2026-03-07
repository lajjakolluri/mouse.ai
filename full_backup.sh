#!/bin/bash
# Full backup before semantic cache implementation

BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$HOME/tokenopt_backups"
BACKUP_NAME="before_semantic_cache_${BACKUP_DATE}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

mkdir -p "${BACKUP_PATH}"

echo "🔒 Creating full backup: ${BACKUP_NAME}"

# 1. Backup database
echo "📊 Backing up database..."
docker exec tokenopt-db pg_dump -U admin -d tokenoptimizer -F c \
    > "${BACKUP_PATH}/database.dump"

# 2. Backup all code
echo "💻 Backing up code..."
cp -r ~/tokenoptimizer-pro "${BACKUP_PATH}/code/"

# 3. Backup .env (encrypted keys!)
echo "🔑 Backing up .env..."
cp .env "${BACKUP_PATH}/.env.backup"

# 4. Backup docker configs
echo "🐳 Backing up Docker configs..."
cp docker-compose.yml "${BACKUP_PATH}/"
cp Dockerfile "${BACKUP_PATH}/"

# 5. Create restore instructions
cat > "${BACKUP_PATH}/RESTORE.md" << 'RESTORE'
# Restore Instructions

## To restore this backup:

1. Stop services:
   cd ~/tokenoptimizer-pro
   sudo docker-compose down

2. Restore database:
   docker exec -i tokenopt-db pg_restore -U admin -d tokenoptimizer -c \
     < database.dump

3. Restore code:
   cp -r code/* ~/tokenoptimizer-pro/

4. Restore .env:
   cp .env.backup ~/tokenoptimizer-pro/.env

5. Restart:
   sudo docker-compose up -d

RESTORE

# Compress
cd "${BACKUP_DIR}"
tar -czf "${BACKUP_NAME}.tar.gz" "${BACKUP_NAME}/"
rm -rf "${BACKUP_NAME}/"

BACKUP_SIZE=$(du -sh "${BACKUP_NAME}.tar.gz" | cut -f1)

echo "✅ Backup complete!"
echo "📦 File: ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
echo "💾 Size: ${BACKUP_SIZE}"
echo ""
echo "Download command:"
echo "scp ubuntu@129.159.45.114:${BACKUP_DIR}/${BACKUP_NAME}.tar.gz ."
