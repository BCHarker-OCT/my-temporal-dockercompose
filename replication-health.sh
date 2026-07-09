#!/usr/bin/env bash

echo "Checking health on localhost:7233. If the single-cluster stack is running, this endpoint is expected to report cluster name 'active'."
temporal --address 127.0.0.1:7233 operator cluster health

echo "Checking health on localhost:2233. This should be the replication c2 frontend."
temporal --address 127.0.0.1:2233 operator cluster health

echo "Describing localhost:7233. Expect 'active' when the single-cluster stack owns port 7233; expect 'c1' only when the replication c1 stack is the process bound there."
temporal --address 127.0.0.1:7233 operator cluster describe -o json | jq .clusterName

echo "Describing localhost:2233. Expected cluster name: 'c2'."

temporal --address 127.0.0.1:2233 operator cluster describe -o json | jq .clusterName

echo "Inspecting temporalc1 container IP inside Docker networking."

docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' temporalc1
echo "Inspecting temporalc2 container IP inside Docker networking."
docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' temporalc2
