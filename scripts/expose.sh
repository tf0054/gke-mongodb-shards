#!/bin/sh
kubectl expose service mongos-router-service --type=LoadBalancer --name=my-service-ip
kubectl get svc
