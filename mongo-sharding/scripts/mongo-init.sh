#!/bin/bash
set -e

###
# Инициализация шардированного кластера MongoDB
###

# Ждём, пока узел реплики станет PRIMARY
WAIT_PRIMARY='while (!db.hello().isWritablePrimary) { sleep(1000) }'

echo ">>> Инициализация сервера конфигурации"
docker compose exec -T configSrv mongosh --port 27017 --quiet <<EOF
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [ { _id: 0, host: "configSrv:27017" } ]
});
${WAIT_PRIMARY}
EOF

echo ">>> Инициализация шарда 1"
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1",
  members: [ { _id: 0, host: "shard1:27018" } ]
});
${WAIT_PRIMARY}
EOF

echo ">>> Инициализация шарда 2"
docker compose exec -T shard2 mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: "shard2",
  members: [ { _id: 0, host: "shard2:27019" } ]
});
${WAIT_PRIMARY}
EOF

echo ">>> Подключение шардов к роутеру, включение шардирования и наполнение данными"
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
sh.addShard("shard1/shard1:27018");
sh.addShard("shard2/shard2:27019");

sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name": "hashed" });

use somedb
for (var i = 0; i < 1000; i++) db.helloDoc.insertOne({ age: i, name: "ly" + i });
print("Всего документов: " + db.helloDoc.countDocuments());
EOF

echo ">>> Количество документов на шардах"
docker compose exec -T shard1 mongosh --port 27018 --quiet --eval 'print("shard1: " + db.getSiblingDB("somedb").helloDoc.countDocuments())'
docker compose exec -T shard2 mongosh --port 27019 --quiet --eval 'print("shard2: " + db.getSiblingDB("somedb").helloDoc.countDocuments())'
