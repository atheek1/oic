#!/bin/sh
#File:exportOICProject.sh
#Version:1.0
#Date:10 MAY 2019
#Author:Atheek Rahuman
echo "=================================================================================================="
echo "				Starting OIC Export 			"
echo "=================================================================================================="

#set target env details
if [ "$ENVIRONMENT" = "UAT" ]
then
	OIC_REST_BASE_URL="https://uatoicic-ruralco.aucom-east-1.oraclecloud.com"
elif [ "$ENVIRONMENT" = "PRD" ]
then
	OIC_REST_BASE_URL="https://prodoicic-ruralco.aucom-east-1.oraclecloud.com"
elif [ "$ENVIRONMENT" = "DEV" ]
then
	OIC_REST_BASE_URL="https://devoicic-ruralco.aucom-east-1.oraclecloud.com"
fi
echo "Target Environment $ENVIRONMENT  REST API Endpoint $OIC_REST_BASE_URL"

echo "debug pwd $PWD"
echo "debug BUILD_ID $BUILD_ID"
echo "debug ENV $ENVIRONMENT"
echo "debug OIC_USER $OIC_USER"

HOME_DIR=$PWD
OUTPUT_DIR=build_$BUILD_ID
mkdir $OUTPUT_DIR
cd $OUTPUT_DIR
mkdir Integrations
mkdir Connections
cd Connections
mkdir $ENVIRONMENT
cd $HOME_DIR
cd $OUTPUT_DIR/Integrations
mkdir $PACKAGE
cd $PACKAGE

echo "Starting building build.json"
echo -e "{" > build.json
echo -e "\t\"package\": {" >> build.json
echo -e "\t\t\"name\":\"$PACKAGE\"," >> build.json
echo -e "\t\t\"integrations\":[" >> build.json
#Downloading package details
echo "Downloading package $PACKAGE details"
CURL_URL="$OIC_REST_BASE_URL/ic/api/integration/v1/packages/$PACKAGE"
CURL_METHOD=GET
HTTP_RESP_CODE=$(curl -s -o package.json  -u "$OIC_USER:$OIC_PASSWORD" -H "Content-Type:application/json"  -X "$CURL_METHOD"   -w "%{http_code}" "$CURL_URL") 
if [ "$HTTP_RESP_CODE" != "200" ] 
	then
		echo "Downloading package details returned unexpected HTTP response code $HTTP_RESP_CODE. Build Job will exit now"
		exit -1
fi	
echo "Package details downloaded"

TOTAL_INTEGRATIONS=$(jq -r '.integrations|length' package.json)
for j in $(seq 0 $(($TOTAL_INTEGRATIONS-1))) ; 
do
	INT_ID=$(jq -r '.integrations['$j'].id' package.json)
	INT_CODE=$(jq -r '.integrations['$j'].code' package.json)
	INT_NAME=$(jq -r '.integrations['$j'].name' package.json)
	INT_VERSION=$(jq -r '.integrations['$j'].version' package.json)
	
	#Downloading integration details
	echo "Downloading integration $INT_ID details"
	CURL_URL="$OIC_REST_BASE_URL/ic/api/integration/v1/integrations/$INT_ID"
	CURL_METHOD=GET
	HTTP_RESP_CODE=$(curl -s -o integration.json  -u "$OIC_USER:$OIC_PASSWORD" -H "Content-Type:application/json"  -X "$CURL_METHOD"   -w "%{http_code}" "$CURL_URL") 
	if [ "$HTTP_RESP_CODE" != "200" ] 
	then
		echo "Downloading integration $INT_ID details returned unexpected HTTP response code $HTTP_RESP_CODE. Build Job will exit now"
		exit -1
	fi
	INT_STATUS=$(jq -r '.status' integration.json)
	INT_TRACING=$(jq -r '.tracingEnabledFlag' integration.json)
	INT_TRACE_PAYLOAD=$(jq -r '.payloadTracingEnabledFlag' integration.json)
	
	
	echo -e "\t\t\t{" >> build.json
	echo -e "\t\t\t\t\"integration\": {" >> build.json
	echo -e "\t\t\t\t\t\"excludeFromBuild\":false," >> build.json
	echo -e "\t\t\t\t\t\"name\":\"$INT_NAME\"," >> build.json
	echo -e "\t\t\t\t\t\"id\":\"$INT_CODE\"," >> build.json
	echo -e "\t\t\t\t\t\"version\":\"$INT_VERSION\"," >> build.json
	echo -e "\t\t\t\t\t\"status\":\"$INT_STATUS\"," >> build.json
	echo -e "\t\t\t\t\t\"tracking\":\"$INT_TRACING\"," >> build.json
	echo -e "\t\t\t\t\t\"trackPayload\":\"$INT_TRACE_PAYLOAD\"," >> build.json
	echo -e "\t\t\t\t\t\"connections\":[" >> build.json
	
	TOTAL_CONNECTIONS=$(jq -r '.dependencies.connections|length' integration.json)
	for k in $(seq 0 $(($TOTAL_CONNECTIONS-1))) ; 
	do
		CONNECTION_ID=$(jq -r '.dependencies.connections['$k'].id' integration.json)
		
		echo -e "\t\t\t\t\t\t{" >> build.json
		echo -e "\t\t\t\t\t\t\t\"connection\": {" >> build.json
		echo -e "\t\t\t\t\t\t\t\t\"excludeFromBuild\":false," >> build.json
		echo -e "\t\t\t\t\t\t\t\t\"id\":\"$CONNECTION_ID\"," >> build.json
		echo -e "\t\t\t\t\t\t\t\t\"passwordTokens\":[]," >> build.json
		echo -e "\t\t\t\t\t\t\t\t\"attachments\":[]" >> build.json
		echo -e "\t\t\t\t\t\t\t}" >> build.json
		
		if [ "$k" -lt "$(($TOTAL_CONNECTIONS-1))" ] 
		then
			echo -e "\t\t\t\t\t\t}," >> build.json
		else
			echo -e "\t\t\t\t\t\t}" >> build.json
		fi
		#Downloading connection details
		echo "Downloading connection $CONNECTION_ID details"
		CURL_URL="$OIC_REST_BASE_URL/ic/api/integration/v1/connections/$CONNECTION_ID"
		CURL_METHOD=GET
		HTTP_RESP_CODE=$(curl -s -o connection.json  -u "$OIC_USER:$OIC_PASSWORD" -H "Content-Type:application/json"  -X "$CURL_METHOD"   -w "%{http_code}" "$CURL_URL") 
		if [ "$HTTP_RESP_CODE" != "200" ] 
		then
		echo "Downloading connection $CONNECTION_ID details returned unexpected HTTP response code $HTTP_RESP_CODE. Build Job will exit now"
		exit -1
		fi
		sed -i -n '5p' connection.json
		CONNECTION_HOME=$HOME_DIR/$OUTPUT_DIR/Connections/$ENVIRONMENT
		CONNECTION_FILE=$CONNECTION_HOME/$CONNECTION_ID.json
		if [ -s $CONNECTON_HOME/$CONNECTION_ID.json ]
		then
			echo "$CONNECTION_ID.json already created from a previous integration in the build. Will not recreate"
		else
			echo "Creating $CONNECTION_ID.json"
			echo "{" >  $CONNECTION_FILE
			AGENT_GROUP_ID=$(jq -r '.agentGroupId' connection.json)
			CONNECTION_PROPERTIES=$(jq -r '.connectionProperties' connection.json)
			SECURITY_POLICY=$(jq -r '.securityPolicy' connection.json)
			SECURITY_PROPERTIES=$(jq -r '.securityProperties' connection.json)
			STATUS=$(jq -r '.status' connection.json)
			
			
			if [ "$AGENT_GROUP_ID" != "null" ] && [ "$AGENT_GROUP_ID" != "NULL" ]
			then
				
				
				echo "\"agentGroupId\":\"$AGENT_GROUP_ID\"," >> $CONNECTION_FILE
				
			fi
			
			if [ "$CONNECTION_PROPERTIES" != "null" ] && [ "$CONNECTION_PROPERTIES" != "NULL" ]
			then
				
				echo "\"connectionProperties\":$CONNECTION_PROPERTIES," >> $CONNECTION_FILE
				
			fi
			
			if [ "$SECURITY_POLICY" != "null" ] && [ "$SECURITY_POLICY" != "NULL" ]
			then
				
				echo "\"securityPolicy\":\"$SECURITY_POLICY\"," >> $CONNECTION_FILE
				
			fi
			
			if [ "$SECURITY_PROPERTIES" != "null" ] && [ "$SECURITY_PROPERTIES" != "NULL" ]
			then
				
				echo "\"securityProperties\":$SECURITY_PROPERTIES," >> $CONNECTION_FILE
			fi
			
			echo "\"status\":\"$STATUS\"" >> $CONNECTION_FILE
			
			echo "}" >>  $CONNECTION_FILE
			echo "Created $CONNECTION_ID.json"
		fi
		rm -f connection.json
		echo "Downloaded connection $CONNECTION_ID details & created $CONNECTION_ID.json "
		
		
	done
	echo -e "\t\t\t\t\t]" >> build.json
	echo -e "\t\t\t\t}" >> build.json
	if [ "$j" -lt "$(($TOTAL_INTEGRATIONS-1))" ] 
	then
		echo -e "\t\t\t}," >> build.json
	else
		echo -e "\t\t\t}" >> build.json
	fi
	
	echo "Downloaded integration $INT_ID details and updated build.json"
	rm -f integration.json
	
	#Exporting integration archive
	echo "Exporting integration $INT_ID archive"
	CURL_URL="$OIC_REST_BASE_URL/ic/api/integration/v1/integrations/$INT_ID/archive"
	CURL_METHOD=GET
	HTTP_RESP_CODE=$(curl -s -o "$INT_CODE"_"$INT_VERSION".iar  -u "$OIC_USER:$OIC_PASSWORD"   -X "$CURL_METHOD"   -w "%{http_code}" "$CURL_URL") 
	if [ "$HTTP_RESP_CODE" != "200" ] 
	then
		echo "Exporting integration $INT_ID archive returned unexpected HTTP response code $HTTP_RESP_CODE. Build Job will exit now"
		exit -1
	fi
	echo "Exported integration $INT_ID archive"
done	

rm -f package.json

echo -e "\t\t]" >> build.json
echo -e "\t}" >> build.json
echo -e "}" >> build.json
echo "Built built.json successfully"

cd $HOME_DIR/$OUTPUT_DIR

zip -r $OUTPUT_DIR.zip ./Integrations ./Connections 
mv $OUTPUT_DIR.zip ..

#clean workspace
echo "Cleaning workspace"
cd ..
rm -r $OUTPUT_DIR


