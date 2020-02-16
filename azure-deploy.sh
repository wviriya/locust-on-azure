#!/bin/bash

# Strict mode, fail on any error
set -euo pipefail

# Azure configuration
FILE=".env"
if [[ -f $FILE ]]; then
    export $(egrep . $FILE | xargs -n1)
else
	cat << EOF > .env
HOST=""
TEST_CLIENTS=2
RESOURCE_GROUP=""
AZURE_STORAGE_ACCOUNT=""
EOF
	echo "Enviroment file not detected."
	echo "Please configure values for your enviuroment in the created .env file"
	echo "and run the script again."
	echo "TEST_CLIENTS: Number of locust client to create"
	echo "HOST: REST Endpoint to test"
	echo "RESOURCE_GROUP: Resource group where Locust will be deployed"
	echo "AZURE_STORAGE_ACCOUNT: Storage account name that will be created to host the locust file"
	exit 1
fi

echo "starting"
cat << EOF > log.txt
EOF

echo "creating storage account: $AZURE_STORAGE_ACCOUNT" | tee log.txt
az storage account create -n $AZURE_STORAGE_ACCOUNT -g $RESOURCE_GROUP --sku Standard_LRS \
	-o json >> log.txt	
	
echo "retrieving storage connection string" | tee log.txt
AZURE_STORAGE_CONNECTION_STRING=$(az storage account show-connection-string --name $AZURE_STORAGE_ACCOUNT -g $RESOURCE_GROUP -o tsv)

echo 'creating file share' | tee log.txt
az storage share create -n locust --connection-string $AZURE_STORAGE_CONNECTION_STRING \
	-o json >> log.txt

echo 'uploading simulator scripts' | tee log.txt
az storage file upload -s locust --source locustfile.py --connection-string $AZURE_STORAGE_CONNECTION_STRING \
    -o json >> log.txt

echo "deploying locust ($TEST_CLIENTS clients)..." | tee log.txt
LOCUST_MONITOR=$(az group deployment create -g $RESOURCE_GROUP \
	--template-file locust-arm-template.json \
	--parameters \
		host=$HOST \
		storageAccountName=$AZURE_STORAGE_ACCOUNT \
		fileShareName=locust \
		numberOfInstances=$TEST_CLIENTS \
	--query properties.outputs.locustMonitor.value \
	-o tsv \
	)
sleep 10

echo "locust: endpoint: $LOCUST_MONITOR" | tee log.txt

echo "locust: starting ..." | tee log.txt
declare USER_COUNT=$((150*$TEST_CLIENTS))
declare HATCH_RATE=$((5*$TEST_CLIENTS))
echo "locust: users: $USER_COUNT, hatch rate: $HATCH_RATE"
curl -fsL $LOCUST_MONITOR/swarm -X POST -F "locust_count=$USER_COUNT" -F "hatch_rate=$HATCH_RATE" >> log.txt

echo "locust: monitor available at: $LOCUST_MONITOR" | tee log.txt

echo "done" | tee log.txt