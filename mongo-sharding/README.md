# pymongo-api: шардирование MongoDB

Конфигурация из сервера конфигурации, двух шардов и роутера. Приложение подключается к MongoDB через роутер.

| Сервис          | Роль                                    | Порт  |
|-----------------|-----------------------------------------|-------|
| `configSrv`     | сервер конфигурации (реплика `config_server`) | 27017 |
| `shard1`        | 1-й шард (реплика `shard1`)             | 27018 |
| `shard2`        | 2-й шард (реплика `shard2`)             | 27019 |
| `mongos_router` | роутер `mongos`                          | 27020 |
| `pymongo_api`   | приложение                              | 8080  |

Коллекция `somedb.helloDoc` шардируется по хешу поля `name`, поэтому документы распределяются между шардами примерно поровну.

## Как запустить

Все команды выполняются из директории `mongo-sharding`:

```shell
cd mongo-sharding
```

Если запущена конфигурация из корня репозитория, сначала остановите её. Обе конфигурации используют контейнер с именем `pymongo_api` и порт 8080:

```shell
docker compose -f ../compose.yaml down
```

Запускаем MongoDB и приложение:

```shell
docker compose up -d
```

Инициализируем шардирование и заполняем MongoDB данными. Скрипт создаёт реплики, подключает шарды к роутеру, включает шардирование коллекции `helloDoc` и добавляет 1000 документов:

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

В ответе должны быть `"mongo_is_mongos": true`, список шардов в поле `shards` и 1000 документов в коллекции `helloDoc`.

### Проверка распределения данных по шардам

Общее количество документов через роутер:

```shell
docker compose exec -T mongos_router mongosh --port 27020 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()"
```

Количество документов на каждом шарде:

```shell
docker compose exec -T shard1 mongosh --port 27018 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()"
docker compose exec -T shard2 mongosh --port 27019 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments()"
```

Сумма по шардам равна общему количеству.

## Доступные эндпоинты

Список доступных эндпоинтов, swagger http://<ip виртуальной машины>:8080/docs

## Как остановить

```shell
docker compose down      # остановить контейнеры, данные сохранятся
docker compose down -v   # остановить и удалить данные (потом снова нужен ./scripts/mongo-init.sh)
```
