# Как запустить и проверить

## 1. Запустите приложение

Убедиться, что находишься в каталоге `mongo-sharding`

```shell
docker compose up -d
```

## 2. Инициализация

Инициализируем бд: настраиваем replica set для config-сервера, шардов и подключаем их к маршрутизатору mongos

```shell
bash scripts/mongo-init.sh
```

## 3. Опрашиваем данные

1. Сколько всего записей в коллекции `helloDoc`.

```shell
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

2. Из них на первом шарде.

```shell
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

3. Из них на втором шарде.

```shell
docker compose exec -T shard2 mongosh --port 27019 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

4. Получение количества записей через API
```shell
curl http://localhost:8080/helloDoc/count
```

---

## На случай перезапуска

```shell
docker compose down -v
```

И потом можно заново заполнять.