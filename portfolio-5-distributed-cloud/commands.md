# Portfolio 5: commands I ran

## Create data folders (PowerShell)
```
mkdir C:\data\rs\n1, C:\data\rs\n2, C:\data\rs\n3
```

## Start three nodes (one PowerShell tab each)
```
& "C:\Program Files\MongoDB\Server\9.0\bin\mongod.exe" --replSet naijamartRS --port 27018 --dbpath C:\data\rs\n1 --bind_ip localhost
& "C:\Program Files\MongoDB\Server\9.0\bin\mongod.exe" --replSet naijamartRS --port 27019 --dbpath C:\data\rs\n2 --bind_ip localhost
& "C:\Program Files\MongoDB\Server\9.0\bin\mongod.exe" --replSet naijamartRS --port 27020 --dbpath C:\data\rs\n3 --bind_ip localhost
```

## Create the replica set (once, in mongosh connected to 27018)
```
rs.initiate({ _id: "naijamartRS", members: [ { _id: 0, host: "localhost:27018" }, { _id: 1, host: "localhost:27019" }, { _id: 2, host: "localhost:27020" } ] })
```

## Connect to the whole set
```
mongosh "mongodb://localhost:27018,localhost:27019,localhost:27020/?replicaSet=naijamartRS"
```

## Check status
```
rs.status().members.map(m => m.name + "  " + m.stateStr + "  health=" + m.health)
```

## Connect straight to one secondary
```
mongosh "mongodb://localhost:27020/?directConnection=true&readPreference=secondary"
```

## Failover test
Ctrl+C in the primary's tab, wait about 10 seconds, check status, then:
```
db.products.updateOne({ product_id: 1 }, { $set: { failover_demo: "written while one node was down" } })
```
Restart the stopped node, then on it:
```
db.products.findOne({ product_id: 1 }, { product_id: 1, failover_demo: 1 })
```
Clean up:
```
db.products.updateOne({ product_id: 1 }, { $unset: { failover_demo: "" } })
```

## CAP test
Stop two nodes, connect to the survivor with `?directConnection=true`:
```
rs.status().members.map(m => m.name + "  " + m.stateStr)
db.products.updateOne({ product_id: 1 }, { $set: { cap_demo: "should be refused" } })
db.getMongo().setReadPref("secondaryPreferred")
db.products.countDocuments()
```
Then restart the two nodes and check status again.
