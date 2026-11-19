# pymongo-api: шардирование, репликация и кеширование

Конфигурация из сервера конфигурации, двух шардов и роутера. Каждый шард — реплика из трёх узлов: один PRIMARY и два SECONDARY. Приложение подключается к MongoDB через роутер и кеширует ответы в Redis.

| Сервис          | Роль                                          | Порт  |
|-----------------|-----------------------------------------------|-------|
| `configSrv`     | сервер конфигурации (реплика `config_server`) | 27017 |
| `shard1-1`      | 1-й шард, реплика `shard1` (PRIMARY)          | 27018 |
| `shard1-2`      | 1-й шард, реплика `shard1` (SECONDARY)        | 27021 |
| `shard1-3`      | 1-й шард, реплика `shard1` (SECONDARY)        | 27022 |
| `shard2-1`      | 2-й шард, реплика `shard2` (PRIMARY)          | 27019 |
| `shard2-2`      | 2-й шард, реплика `shard2` (SECONDARY)        | 27023 |
| `shard2-3`      | 2-й шард, реплика `shard2` (SECONDARY)        | 27024 |
| `mongos_router` | роутер `mongos`                               | 27020 |
| `redis`         | кеш приложения                                | 6379  |
| `pymongo_api`   | приложение                                    | 8080  |

Коллекция `somedb.helloDoc` шардируется по хешу поля `name`, поэтому документы распределяются между шардами примерно поровну. Внутри шарда каждый документ копируется на все три узла реплики.

Кеширование включается переменной окружения `REDIS_URL: "redis://redis:6379"` у сервиса `pymongo_api`. Кешируется эндпоинт `/<collection_name>/users`, ответ хранится в Redis 60 секунд.

## Как запустить

Все команды выполняются из директории `sharding-repl-cache`:

```shell
cd sharding-repl-cache
```

Если запущена конфигурация из корня репозитория, из `mongo-sharding` или из `mongo-sharding-repl`, сначала остановите её. Конфигурации используют одинаковые имена контейнеров и порты:

```shell
docker compose -f ../compose.yaml down
docker compose -f ../mongo-sharding/compose.yaml down
docker compose -f ../mongo-sharding-repl/compose.yaml down
```

Запускаем MongoDB и приложение:

```shell
docker compose up -d
```

Инициализируем реплики и шардирование и заполняем MongoDB данными. Скрипт создаёт реплики из трёх узлов для каждого шарда, подключает шарды к роутеру, включает шардирование коллекции `helloDoc` и добавляет 1000 документов:

```shell
./scripts/mongo-init.sh
```

Скрипт выполняется один раз, при первом запуске. Данные хранятся в томах, поэтому при последующих `docker compose up -d` кластер поднимается уже настроенным.

## Как проверить

### Если вы запускаете проект на локальной машине

Откройте в браузере http://localhost:8080

### Если вы запускаете проект на предоставленной виртуальной машине

Узнать белый ip виртуальной машины

```shell
curl --silent http://ifconfig.me
```

Откройте в браузере http://<ip виртуальной машины>:8080

В ответе должны быть `"mongo_is_mongos": true`, список шардов в поле `shards` (у каждого — три узла), `"cache_enabled": true` и 1000 документов в коллекции `helloDoc`.

### Проверка распределения данных по шардам

Общее количество документов через роутер:

```shell
docker compose exec -T mongos_router mongosh --port 27020 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()"
```

Количество документов на каждом шарде (на PRIMARY-узлах):

```shell
docker compose exec -T shard1-1 mongosh --port 27018 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()"
docker compose exec -T shard2-1 mongosh --port 27019 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()"
```

Сумма по шардам равна общему количеству.

### Проверка репликации

Состав и состояние реплик — у каждой должно быть три узла, один `PRIMARY` и два `SECONDARY`:

```shell
docker compose exec -T shard1-1 mongosh --port 27018 --quiet --eval "rs.status().members.forEach(m => print(m.name, m.stateStr))"
docker compose exec -T shard2-1 mongosh --port 27019 --quiet --eval "rs.status().members.forEach(m => print(m.name, m.stateStr))"
```

Количество документов на SECONDARY-узлах должно совпадать с PRIMARY своего шарда:

```shell
docker compose exec -T shard1-2 mongosh --port 27021 --quiet --eval "db.getMongo().setReadPref('secondaryPreferred'); db.getSiblingDB('somedb').helloDoc.countDocuments()"
docker compose exec -T shard1-3 mongosh --port 27022 --quiet --eval "db.getMongo().setReadPref('secondaryPreferred'); db.getSiblingDB('somedb').helloDoc.countDocuments()"
docker compose exec -T shard2-2 mongosh --port 27023 --quiet --eval "db.getMongo().setReadPref('secondaryPreferred'); db.getSiblingDB('somedb').helloDoc.countDocuments()"
docker compose exec -T shard2-3 mongosh --port 27024 --quiet --eval "db.getMongo().setReadPref('secondaryPreferred'); db.getSiblingDB('somedb').helloDoc.countDocuments()"
```

### Проверка кеширования

Выполните один и тот же запрос несколько раз подряд и сравните время. Первый запрос идёт в MongoDB, повторные в течение 60 секунд отдаются из Redis и выполняются заметно быстрее.

bash (Linux, macOS, Git Bash):

```shell
for i in 1 2 3; do curl -s -o /dev/null -w "%{time_total}s\n" http://localhost:8080/helloDoc/users; done
```

PowerShell:

```powershell
1..3 | ForEach-Object { "{0:N3}s" -f (Measure-Command { Invoke-WebRequest -UseBasicParsing http://localhost:8080/helloDoc/users | Out-Null }).TotalSeconds }
```

Ключи кеша в Redis:

```shell
docker compose exec -T redis redis-cli keys "api:cache*"
```

## Доступные эндпоинты

Список доступных эндпоинтов, swagger http://<ip виртуальной машины>:8080/docs

## Как остановить

```shell
docker compose down      # остановить контейнеры, данные сохранятся
docker compose down -v   # остановить и удалить данные (потом снова нужен ./scripts/mongo-init.sh)
```
