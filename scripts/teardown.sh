#!/bin/sh
##
# Script to remove/undepoy all project resources from GKE & GCE.
##


#Give your name as kubernetes namespace
namespace='daemonsl'

diskType="k8s-mongodb-"$namespace

# KEEP Config DB size (10-25 GB) very less than Main DB
# Main DB Servers DISK
mainDB_SSD_DISK_inGB="10"

# Config Server DISK
configDB_SSD_DISK_inGB="5"

#--------------------------------------------

# Delete mongos deployment + mongod stateful set + mongodb service + secrets + host vm configurer daemonset
kubectl delete deployments mongos --namespace=${namespace}
#kubectl delete services mongos-headless-service --namespace=${namespace}

kubectl delete statefulsets mongodb-shard1 --namespace=${namespace} --force --grace-period=0 --cascade=false
kubectl delete services mongodb-shard1-headless-service --namespace=${namespace}

kubectl delete statefulsets mongodb-shard2 --namespace=${namespace} --force --grace-period=0 --cascade=false
kubectl delete services mongodb-shard2-headless-service --namespace=${namespace}

kubectl delete statefulsets mongodb-configdb  --namespace=${namespace} --force --grace-period=0 --cascade=false
kubectl delete services mongodb-configdb-headless-service --namespace=${namespace}
sleep 3

# Delete persistent volume claims
kubectl delete persistentvolumeclaims -l role=mongodb-shard1 --namespace=${namespace}
kubectl delete persistentvolumeclaims -l role=mongodb-shard2 --namespace=${namespace}
sleep 3

# dont know why but needed
kubectl delete pod mongodb-configdb-0 --namespace=${namespace}
kubectl delete pod mongodb-shard1-0 --namespace=${namespace}
kubectl delete pod mongodb-shard2-0 --namespace=${namespace}

# Delete persistent volumes
for i in 1 2
do
    kubectl delete persistentvolumes data-volume-${diskType}-${mainDB_SSD_DISK_inGB}g-${i}
done
for i in 1
do
    kubectl delete persistentvolumes data-volume-${diskType}-${configDB_SSD_DISK_inGB}g-${i}
done
sleep 30

# Delete GCE disks
for i in 1 2
do
    gcloud -q compute disks delete pd-ssd-disk-${diskType}-${mainDB_SSD_DISK_inGB}g-$i
done

for i in 1
do
    gcloud -q compute disks delete pd-ssd-disk-${diskType}-${configDB_SSD_DISK_inGB}g-$i
done
