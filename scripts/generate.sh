#!/bin/sh
##
# Script to deploy a Kubernetes project with a StatefulSet running a MongoDB Sharded Cluster, to GKE.
##

MONGO_NUM=6

# Create new GKE Kubernetes cluster (using host node VM images based on Ubuntu
# rather than default ChromiumOS & also use slightly larger VMs than default)
echo "Creating GKE Cluster"
gcloud alpha container clusters create "audio-analyzer-mongodb-cluster" --image-type=ubuntu \
  --machine-type=n1-standard-4 \
  --enable-kubernetes-alpha \
  --local-ssd-count=1 \
  --cluster-version="1.9.6-gke.0" \
  --num-nodes=8

# Configure host VM using daemonset to disable hugepages
echo "Deploying GKE Daemon Set"
kubectl apply -f ../resources/hostvm-node-configurer-daemonset.yaml


# Define storage class for dynamically generated persistent volumes
# NOT USED IN THIS EXAMPLE AS EXPLICITLY CREATING DISKS FOR USE BY PERSISTENT
# VOLUMES, HENCE COMMENTED OUT BELOW
#kubectl apply -f ../resources/gce-ssd-storageclass.yaml


# Register GCE Fast SSD persistent disks and then create the persistent disks 
echo "Creating GCE disks"
for i in 1
do
    # 4GB disks    
    gcloud compute disks create --size 4GB --type pd-ssd pd-ssd-disk-4g-$i
done
#for i in `seq 1 $MONGO_NUM`;
#do
#    # 8 GB disks
#    gcloud compute disks create --size 8GB --type pd-ssd pd-ssd-disk-8g-$i
#done
#sleep 3


# Create persistent volumes using disks that were created above
echo "Creating GKE Persistent Volumes"
for i in 1
do
    # Replace text stating volume number + size of disk (set to 4)
    sed -e "s/INST/${i}/g; s/SIZE/4/g" ../resources/xfs-gce-ssd-persistentvolume.yaml > /tmp/xfs-gce-ssd-persistentvolume.yaml
    kubectl apply -f /tmp/xfs-gce-ssd-persistentvolume.yaml
done
#for i in `seq 1 $MONGO_NUM`;
#do
#    # Replace text stating volume number + size of disk (set to 8)
#    sed -e "s/INST/${i}/g; s/SIZE/8/g" ../resources/xfs-gce-ssd-persistentvolume.yaml > /tmp/xfs-gce-ssd-persistentvolume.yaml
#    kubectl apply -f /tmp/xfs-gce-ssd-persistentvolume.yaml
#done
#rm /tmp/xfs-gce-ssd-persistentvolume.yaml
#sleep 3


# Create keyfile for the MongoDB cluster as a Kubernetes shared secret
TMPFILE=$(mktemp)
/usr/bin/openssl rand -base64 741 > $TMPFILE
kubectl create secret generic shared-bootstrap-data --from-file=internal-auth-mongodb-keyfile=$TMPFILE
rm $TMPFILE


# Deploy a MongoDB ConfigDB Service ("Config Server Replica Set") using a Kubernetes StatefulSet
echo "Deploying GKE StatefulSet & Service for MongoDB Config Server Replica Set"
kubectl apply -f ../resources/mongodb-configdb-service.yaml


# Deploy each MongoDB Shard Service using a Kubernetes StatefulSet
echo "Deploying GKE StatefulSet & Service for each MongoDB Shard Replica Set"
for i in `seq 1 $MONGO_NUM`;
do
  sed -e "s/shardX/shard$i/g; s/ShardX/Shard$i/g" ../resources/mongodb-maindb-service.yaml > /tmp/mongodb-maindb-service.yaml
  kubectl apply -f /tmp/mongodb-maindb-service.yaml
done

#sed -e 's/shardX/shard2/g; s/ShardX/Shard2/g' ../resources/mongodb-maindb-service.yaml > /tmp/mongodb-maindb-service.yaml
#kubectl apply -f /tmp/mongodb-maindb-service.yaml
#sed -e 's/shardX/shard3/g; s/ShardX/Shard3/g' ../resources/mongodb-maindb-service.yaml > /tmp/mongodb-maindb-service.yaml
#kubectl apply -f /tmp/mongodb-maindb-service.yaml
rm /tmp/mongodb-maindb-service.yaml


# Deploy some Mongos Routers using a Kubernetes StatefulSet
echo "Deploying GKE Deployment & Service for some Mongos Routers"
kubectl apply -f ../resources/mongodb-mongos-service.yaml


# Wait until the final mongod of each Shard + the ConfigDB has started properly
echo
echo "Waiting for all the shards and configdb containers to come up (`date`)..."
echo " (IGNORE any reported not found & connection errors)"
sleep 30
echo -n "  "
until kubectl --v=0 exec mongod-configdb-0 -c mongod-configdb-container -- mongo --quiet --eval 'db.getMongo()'; do
    sleep 5
    echo -n "  "
done

TMP_MAX=`expr $MONGO_NUM - 1`
#for i in `seq 0 $TMP_MAX`;
#do
#  echo -n "  "
#  until kubectl --v=0 exec mongod-shard1-$i -c mongod-shard1-container -- mongo --quiet --eval 'db.getMongo()'; do
#    sleep 5
#    echo -n "  "
#  done
#done

for i in `seq 1 $MONGO_NUM`;
do
  until kubectl --v=0 exec mongod-shard$i-0 -c mongod-shard$i-container -- mongo --quiet --eval 'db.getMongo()'; do
    sleep 5
    echo -n "  "
  done
done

#echo -n "  "
#until kubectl --v=0 exec mongod-shard2-0 -c mongod-shard2-container -- mongo --quiet --eval 'db.getMongo()'; do
#    sleep 5
#    echo -n "  "
#done
#echo -n "  "
#until kubectl --v=0 exec mongod-shard3-0 -c mongod-shard3-container -- mongo --quiet --eval 'db.getMongo()'; do
#    sleep 5
#    echo -n "  "
#done
echo "...shards & configdb containers are now running (`date`)"
echo


# Initialise the Config Server Replica Set and each Shard Replica Set
echo "Configuring Config Server's & each Shard's Replica Sets"

kubectl exec mongod-configdb-0 -c mongod-configdb-container -- mongo --eval 'rs.initiate({_id: "ConfigDBRepSet", version: 1, members: [ {_id: 0, host: "mongod-configdb-0.mongodb-configdb-service.default.svc.cluster.local:27017"} ]});'

SHARD_LINES="[ "
for i in `seq 1 $TMP_MAX`;
do
  SHARD_LINES=$SHARD_LINES"{_id: $i, host: \"mongod-shard1-$i.mongodb-shard1-service.default.svc.cluster.local:27017\"}, "
done
SHARD_LINES=$SHARD_LINES"{_id: 0, host: \"mongod-shard1-0.mongodb-shard1-service.default.svc.cluster.local:27017\"} ]"

echo $SHARD_LINES


for i in `seq 1 $MONGO_NUM`;
do
  kubectl exec mongod-shard$i-0 -c mongod-shard$i-container -- mongo --eval 'rs.initiate({_id: "Shard'$i'RepSet", version: 1, members: [{_id: 0, host: "mongod-shard'$i'-0.mongodb-shard'$i'-service.default.svc.cluster.local:27017"}]});'
done

#kubectl exec mongod-shard2-0 -c mongod-shard2-container -- mongo --eval 'rs.initiate({_id: "Shard2RepSet", version: 1, members: [ {_id: 0, host: "mongod-shard2-0.mongodb-shard2-service.default.svc.cluster.local:27017"}, {_id: 1, host: "mongod-shard2-1.mongodb-shard2-service.default.svc.cluster.local:27017"} ]});'
#kubectl exec mongod-shard3-0 -c mongod-shard3-container -- mongo --eval 'rs.initiate({_id: "Shard3RepSet", version: 1, members: [ {_id: 0, host: "mongod-shard3-0.mongodb-shard3-service.default.svc.cluster.local:27017"}, {_id: 1, host: "mongod-shard3-1.mongodb-shard3-service.default.svc.cluster.local:27017"} ]});'
echo


# Wait for each MongoDB Shard's Replica Set + the ConfigDB Replica Set to each have a primary ready
echo "Waiting for all the MongoDB ConfigDB & Shards Replica Sets to initialise..."
kubectl exec mongod-configdb-0 -c mongod-configdb-container -- mongo --quiet --eval 'while (rs.status().hasOwnProperty("myState") && rs.status().myState != 1) { print("."); sleep(1000); };'

for i in `seq 1 $MONGO_NUM`;
do
  kubectl exec mongod-shard$i-0 -c mongod-shard$i-container -- mongo --quiet --eval 'while (rs.status().hasOwnProperty("myState") && rs.status().myState != 1) { print("."); sleep(1000); };'
done

#kubectl exec mongod-shard2-0 -c mongod-shard2-container -- mongo --quiet --eval 'while (rs.status().hasOwnProperty("myState") && rs.status().myState != 1) { print("."); sleep(1000); };'
#kubectl exec mongod-shard3-0 -c mongod-shard3-container -- mongo --quiet --eval 'while (rs.status().hasOwnProperty("myState") && rs.status().myState != 1) { print("."); sleep(1000); };'
sleep 2 # Just a little more sleep to ensure everything is ready!
echo "...initialisation of the MongoDB Replica Sets completed"
echo


# Wait for the mongos to have started properly
echo "Waiting for the first mongos to come up (`date`)..."
echo " (IGNORE any reported not found & connection errors)"
echo -n "  "
until kubectl --v=0 exec mongos-router-0 -c mongos-container -- mongo --quiet --eval 'db.getMongo()'; do
    sleep 2
    echo -n "  "
done
echo "...first mongos is now running (`date`)"
echo


# Add Shards to the Configdb
echo "Configuring ConfigDB to be aware of the 3 Shards"
for i in `seq 1 $MONGO_NUM`;
do
  kubectl exec mongos-router-0 -c mongos-container -- mongo --eval 'sh.addShard("Shard'$i'RepSet/mongod-shard'$i'-0.mongodb-shard'$i'-service.default.svc.cluster.local:27017");'
done

#kubectl exec mongos-router-0 -c mongos-container -- mongo --eval 'sh.addShard("Shard2RepSet/mongod-shard2-0.mongodb-shard2-service.default.svc.cluster.local:27017");'
#kubectl exec mongos-router-0 -c mongos-container -- mongo --eval 'sh.addShard("Shard3RepSet/mongod-shard3-0.mongodb-shard3-service.default.svc.cluster.local:27017");'
sleep 3

#
kubectl exec mongos-router-0 -c mongos-container -- mongo admin --eval "printjson(db.runCommand( { enablesharding : 'analysis' } ));"
kubectl exec mongos-router-0 -c mongos-container -- mongo admin --eval 'sh.shardCollection("analysis.hashsignatures", {hashSignature: "hashed"})'

# Print Summary State
kubectl get persistentvolumes
echo
kubectl get all 
echo

