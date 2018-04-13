#!/bin/sh
##
# Script to remove/undepoy all project resources from GKE & GCE.
##

MONGO_NUM=6

# Delete mongos stateful set + mongod stateful set + mongodb service + secrets + host vm configurer daemonset
kubectl delete statefulsets mongos-router
kubectl delete services mongos-router-service
kubectl delete statefulsets mongod-shard1

for i in `seq 1 $MONGO_NUM`;
do
  kubectl delete services mongodb-shard$i-service
done

#kubectl delete statefulsets mongod-shard2
#kubectl delete services mongodb-shard2-service
#kubectl delete statefulsets mongod-shard3
#kubectl delete services mongodb-shard3-service
kubectl delete statefulsets mongod-configdb
kubectl delete services mongodb-configdb-service
#kubectl delete secret shared-bootstrap-data
kubectl delete daemonset hostvm-configurer
sleep 3

# Delete persistent volume claims
kubectl delete persistentvolumeclaims -l tier=maindb
kubectl delete persistentvolumeclaims -l tier=configdb
sleep 3

# Delete persistent volumes
for i in 1
do
    kubectl delete persistentvolumes data-volume-4g-$i
done
#for i in `seq 1 $MONGO_NUM`;
#do
#    kubectl delete persistentvolumes data-volume-8g-$i
#done
sleep 20

# Delete GCE disks
for i in 1
do
    gcloud -q compute disks delete pd-ssd-disk-4g-$i
done
#for i in `seq 1 $MONGO_NUM`;
#do
#    gcloud -q compute disks delete pd-ssd-disk-8g-$i
#done

# Delete whole Kubernetes cluster (including its VM instances)
gcloud alpha -q container clusters delete "audio-analyzer-mongodb-cluster"

