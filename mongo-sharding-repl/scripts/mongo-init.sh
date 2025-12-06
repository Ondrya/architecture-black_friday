#!/bin/bash

# Цвета ANSI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

###
# Инициализируем бд: настраиваем replica set для config-сервера, шардов и подключаем их к маршрутизатору mongos
###

echo -e "${BLUE}[INFO]${NC} Инициализация replica set для config-сервера (configSrv, порт 27017)..."
docker compose exec -T configSrv mongosh --port 27017 <<EOF
rs.initiate(
  {
    _id : "config_server",
    configsvr: true,
    members: [
      { _id : 0, host : "configSrv:27017" }
    ]
  }
);
exit();
EOF
echo -e "${GREEN}[OK]${NC} Config server replica set инициализирован."

echo -e "${BLUE}[INFO]${NC} Инициализация replica set для шарда shard1 (порты 27021 - 27023)..."
docker compose exec -T shard1_1 mongosh --port 27021 <<EOF
rs.initiate(
    {
      _id : "shard1",
      members: [
        { _id : 0, host : "shard1_1:27021" },
        { _id : 1, host : "shard1_2:27022" },
        { _id : 2, host : "shard1_3:27023" }
      ]
    }
);
exit();
EOF
echo -e "${GREEN}[OK]${NC} Shard1 replica set инициализирован."

echo -e "${BLUE}[INFO]${NC} Инициализация replica set для шарда shard2 (порты 27031 - 27033)..."
docker compose exec -T shard2_1 mongosh --port 27031 <<EOF
rs.initiate(
    {
      _id : "shard2",
      members: [
        { _id : 0, host : "shard2_1:27031" },
        { _id : 1, host : "shard2_2:27032" },
        { _id : 2, host : "shard2_3:27033" }
      ]
    }
);
exit();
EOF
echo -e "${GREEN}[OK]${NC} Shard2 replica set инициализирован."

echo -e "${BLUE}[INFO]${NC} Ожидание готовности mongos_router (порт 27020) — отправляем ping до успеха..."
until docker compose exec -T mongos_router mongosh --port 27020 --eval 'db.runCommand({ping: 1})' >/dev/null 2>&1; do
  echo -e "${YELLOW}[WAIT]${NC} mongos_router ещё не готов. Повторная попытка через 30 секунд..."
  sleep 30
done
echo -e "${GREEN}[OK]${NC} mongos_router доступен."

echo -e "${BLUE}[INFO]${NC} Подключение шардов (shard1 и shard2) к кластеру через mongos..."
docker compose exec -T mongos_router mongosh --port 27020 <<EOF
sh.addShard( "shard1/shard1_1:27021");
sh.addShard( "shard2/shard2_1:27031");
EOF
echo -e "${GREEN}[OK]${NC} Шарды успешно добавлены."

echo -e "${BLUE}[INFO]${NC} Включение шардинга для БД 'somedb' и коллекции 'helloDoc' (хеширование по полю 'name')..."
docker compose exec -T mongos_router mongosh --port 27020 <<EOF
sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } );
EOF
echo -e "${GREEN}[OK]${NC} Шардинг включён для somedb.helloDoc."

# === Параметр: количество документов ===
DOC_COUNT=${DOC_COUNT:-1500}  # можно переопределить: DOC_COUNT=10000 ./insert.sh

echo -e "${BLUE}[INFO]${NC} Вставка ${DOC_COUNT} тестовых документов в коллекцию somedb.helloDoc..."
docker compose exec -T mongos_router mongosh --port 27020 <<EOF
use somedb;
print("Вставка ${DOC_COUNT} документов...");
for (let i = 0; i < ${DOC_COUNT}; i++) {
  db.helloDoc.insertOne({ age: i, name: "ly" + i });
}
print("✅ Завершено.");
EOF

echo -e "${GREEN}[OK]${NC} ${DOC_COUNT} документов успешно вставлены."

echo -e "${GREEN}[INFO]${NC} Настройка шардированного кластера завершена."