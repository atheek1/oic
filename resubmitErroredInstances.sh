#!/bin/sh
#File:resubmitErroredInstances.sh
#Version:1.0
#Invoke as ./resubmitErroredInstances <ENV> <Path to Monitored_Integration.json file>  <OIC_USER_NAME> <OIC_USER_PASSWORD>
#where ENV should be one of "DEV" "UAT" or "PRD"
#Date:16 AUGUST 2019
#Author:Atheek Rahuman
echo "=================================================================================================="
echo "				Starting OIC Import 			"
echo "=================================================================================================="

ENV=$1
MON_INT_FILE=$2
OIC_USER=$3
OIC_USER_PASSWORD=$4

#set target env details
if [ "$ENV" = "UAT" ]
then
	OIC_REST_BASE_URL="https://uat-oic-instance.aucom-east-1.oraclecloud.com"
elif [ "$ENV" = "PRD" ]
then
	OIC_REST_BASE_URL="https://prod-oic-instance.aucom-east-1.oraclecloud.com"
elif [ "$ENV" = "DEV" ]
then
	OIC_REST_BASE_URL="https://dev-oic-instance.aucom-east-1.oraclecloud.com"
fi
echo "Target Environment $ENV  REST API Endpoint $OIC_REST_BASE_URL"


#check Monitored_Integration.json 
if [ -s $MON_INT_FILE ]
then
	
	echo "$MON_INT_FILE doesn't exit. Script will exist now"
	exit -1
fi

mkdir REI_WORK_DIR
cd REI_WORK_DIR

#Get monitored integration details
TOTAL_INTEGRATIONS=$(jq -r '.integrations|length' $MON_INT_FILE)
#iterate through the integrations in build file
for i in $(seq 0 $(($TOTAL_INTEGRATIONS-1))) ; 
do	
	
	#read build properties from build file
	INTEGRATION_ID=$(jq -r '.integrations['$i'].id' $MON_INT_FILE)
	INTEGRATION_VERSION=$(jq -r '.integrations['$i'].version' $MON_INT_FILE)
	INTEGRATION_ID=$(jq -r '.integrations['$i'].id' $MON_INT_FILE)
	SKIP_FLAG=$(jq -r '.integrations['$i'].skip' $MON_INT_FILE)
	
	
	echo "=================================================================================================="
	echo "					START PROCESSING INTEGRATION  $(($i+1)) of $TOTAL_INTEGRATIONS"
	echo "					$INTEGRATION_ID $INTEGRATION_VERSION"
	echo "=================================================================================================="
	if [ $SKIP_FLAG = "true" ]
	then
	echo "Skipped  $INTEGRATION_ID_$INTEGRATION_VERSION as it is skipped in $MON_INT_FILE"
	else 
		
		
		#Retrieveing errored instances for the integration
		echo "Retrieving errored instances for the integration"
		CURL_URL="$OIC_REST_BASE_URL/ic/api/integration/v1/monitoring/errors?limit=100&q={timewindow:'1d' , code:'$INTEGRATION_ID', version:'INTEGRATION_VERSION'}"
		CURL_METHOD=GET
		HTTP_RESP_CODE=$(curl  -s -o integration.json -u "$OIC_USER:$OIC_USER_PASSWORD" -H "Content-Type:application/json"  -X "$CURL_METHOD"  -w "%{http_code}" "$CURL_URL") 
		TOTAL_ERRORS=$(jq -r '.items|length' integrations.json)
		echo "Total errored instances for $INTEGRATION_ID $INTEGRATION_VERSION : $TOTAL_ERRORS"
		rm resubmit.json
		echo "{\"ids\" : [" >> resubmit.json
		for j in $(seq 0 $(($TOTAL_ERRORS-1))) ;
		do
			INSTANCE_ID=$(jq -r '.items['$j'].id' integration.json)
			echo $INSTANCE_ID, >>resubmit.json
		done
		cat resubmit.json
		echo "]}" >> resubmit.json
		
		
	fi	
done		
		
		
		


#clean workspace
echo "Cleaning workspace"
cd ..
rm -r REI_WORK_DIR
echo "ResubmitErroredInstances Job completed"		