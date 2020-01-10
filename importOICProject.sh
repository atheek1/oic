#!/bin/sh
#File:importOICProject.sh
#Version:1.0
#Date:06 MAY 2019
#Author:Atheek Rahuman
echo "=================================================================================================="
echo "				Starting OIC Import 			"
echo "=================================================================================================="

#set target env details
if [ "$ENVIRONMENT" = "UAT" ]
then
	OIC_REST_BASE_URL="https://uat-oic-instance.aucom-east-1.oraclecloud.com"
elif [ "$ENVIRONMENT" = "PRD" ]
then
	OIC_REST_BASE_URL="https://prod-oic-instance.aucom-east-1.oraclecloud.com"
elif [ "$ENVIRONMENT" = "DEV" ]
then
	OIC_REST_BASE_URL="https://dev-oic-instance.aucom-east-1.oraclecloud.com"
fi
echo "Target Environment $ENVIRONMENT  REST API Endpoint $OIC_REST_BASE_URL"


#initialise build settings
HOME_DIR=$PWD

 

if [ -s CUSTOM_BUILD_FILE ]
then
	BUILD_FILE=$HOME_DIR/CUSTOM_BUILD_FILE
else
	BUILD_FILE="$HOME_DIR/$BUILD_FILE_PATH/build.json"
fi

#load private key files
if [ -s PRIVATE ]
then
	
	PK_UPLOADED=Y
	mv ./PRIVATE PRIVATE.zip
	mv ./PRIVATE.zip Connections/$ENVIRONMENT/Attachments
	cd Connections/$ENVIRONMENT/Attachments
	unzip PRIVATE.zip
	cd $HOME_DIR
fi

#load passwords
if [ -s PASSWORD ]
then	
	dos2unix ./PASSWORD
	#escape any forward slashes present in password
	sed -i 's/\//\\\//' PASSWORD
	source ./PASSWORD
    export $(cut -d= -f1 PASSWORD)
fi

cd $BUILD_FILE_PATH

#import integrations
TOTAL_INTEGRATIONS=$(jq -r '.package.integrations|length' $BUILD_FILE)
#iterate through the integrations in build file
for i in $(seq 0 $(($TOTAL_INTEGRATIONS-1))) ; 
do	
	
	#read build properties from build file
	BUILD_EXCLUDE_FLAG=$(jq -r '.package.integrations['$i'].integration.excludeFromBuild' $BUILD_FILE)
	INTEGRATION_NAME=$(jq -r '.package.integrations['$i'].integration.name' $BUILD_FILE)
	INTEGRATION_ID=$(jq -r '.package.integrations['$i'].integration.id' $BUILD_FILE)
	INTEGRATION_VERSION=$(jq -r '.package.integrations['$i'].integration.version' $BUILD_FILE)
	INTEGRATION_STATUS=$(jq -r '.package.integrations['$i'].integration.status' $BUILD_FILE)
	TRACKING_FLAG=$(jq -r '.package.integrations['$i'].integration.tracking' $BUILD_FILE)
	TRACK_PAYLOAD_FLAG=$(jq -r '.package.integrations['$i'].integration.trackPayload' $BUILD_FILE)
	ARCHIVE_FILE=$INTEGRATION_ID"_"$INTEGRATION_VERSION".iar"
	
	
	echo "=================================================================================================="
	echo "					START PROCESSING INTEGRATION  $(($i+1)) of $TOTAL_INTEGRATIONS"
	echo "					$INTEGRATION_NAME $INTEGRATION_VERSION"
	echo "=================================================================================================="
	if [ $BUILD_EXCLUDE_FLAG = "true" ]
	then
	echo "Skipped $INTEGRATION_NAME $INTEGRATION_ID_$INTEGRATION_VERSION as it is excluded in build json"
	else 
		
		
		#check if integration exists in target
		echo "Checking Integration Exist in Target"
		CURL_URL="$OIC_REST_BASE_URL/ic/api/integration/v1/integrations/$INTEGRATION_ID|$INTEGRATION_VERSION"
		CURL_METHOD=GET
		HTTP_RESP_CODE=$(curl  -s -o /dev/null -u "$OIC_USER:$OIC_USER_PASSWORD" -H "Content-Type:application/json"  -X "$CURL_METHOD"  -w "%{http_code}" "$CURL_URL") 
		
		
		
		
		#upload archive file to add or replace an integration
		if [ "$HTTP_RESP_CODE" = "404" ]
		then
			echo "Integration doesn't exist"
			CURL_METHOD="POST"
		elif [ "$HTTP_RESP_CODE" = "200" ]
		then
			#existing integration found. Deactivate it before importing latest   
			echo "Integration exist and hence should be stopped before proceeding"  
			
			
			#stop schedule
			echo "Stopping schedule (if any)"
			CURL_URL="$OIC_REST_BASE_URL/ic/api/integration/v1/integrations/$INTEGRATION_ID|$INTEGRATION_VERSION/schedule/stop"
			CURL_METHOD=POST
			HTTP_RESP_CODE=$(curl -s -o /dev/null  -u "$OIC_USER:$OIC_USER_PASSWORD"  -X "$CURL_METHOD"   -w "%{http_code}" "$CURL_URL")
			if [ "$HTTP_RESP_CODE" != "200" ] && [ "$HTTP_RESP_CODE" != "412" ]
				then
				echo "Stopping schedule returned unexpected HTTP response code $HTTP_RESP_CODE. Build Job will exit now"
				exit -1
			fi
			echo "Schedules stopped  or not found"
			
			
			#deactivate
			echo "Deactivating Integration"
			CURL_URL="$OIC_REST_BASE_URL/ic/api/integration/v1/integrations/$INTEGRATION_ID|$INTEGRATION_VERSION"
			CURL_METHOD=POST
			HTTP_RESP_CODE=$(curl -s -o /dev/null  -u "$OIC_USER:$OIC_USER_PASSWORD" -H "Content-Type:application/json" -H "X-HTTP-Method-Override:PATCH" -X "$CURL_METHOD"  --data '{"status":"CONFIGURED"}' -w "%{http_code}" "$CURL_URL") 
			if [ "$HTTP_RESP_CODE" != "200" ] && [ "$HTTP_RESP_CODE" != "412" ]
				then
				echo "Integration deactivation returned unexpected HTTP response code $HTTP_RESP_CODE. Build Job will exit now"
				exit -1
			fi	
			echo "Integration Deactivated"
			CURL_METHOD="PUT"
		else
			echo "Integration Exist Check returned unexpected HTTP response code $HTTP_RESP_CODE. Build Job will exit now"
			exit -1
		fi
		echo "Uploading Archive File"
		CURL_URL="$OIC_REST_BASE_URL/ic/api/integration/v1/integrations/archive"
		HTTP_RESP_CODE=$(curl -s -o /dev/null -u "$OIC_USER:$OIC_USER_PASSWORD"  -X "$CURL_METHOD" -F "file=@$ARCHIVE_FILE" -w "%{http_code}" "$CURL_URL")
		if [ "$HTTP_RESP_CODE" != "200" ] && [ "$HTTP_RESP_CODE" != "204" ]
			then
				echo "Archive upload returned unexpected HTTP response code $HTTP_RESP_CODE. Build Job will exit now"
				exit -1
		fi		
		echo "Archive Uploaded"
		
		
		
		#update connection properties
		cd $HOME_DIR
		cd Connections/$ENVIRONMENT
		echo "Starting update of connection properties"
		TOTAL_CONNECTIONS=$(jq -r '.package.integrations['$i'].integration.connections|length' $BUILD_FILE)
		for j in $(seq 0 $(($TOTAL_CONNECTIONS-1))) ; 
		do 
			CONNECTION_ID=$(jq -r '.package.integrations['$i'].integration.connections['$j'].connection.id' $BUILD_FILE)
			BUILD_EXCLUDE_FLAG=$(jq -r '.package.integrations['$i'].integration.connections['$j'].connection.excludeFromBuild' $BUILD_FILE)
			CONNECTION_FILE=$CONNECTION_ID".json"
			if [ $BUILD_EXCLUDE_FLAG = "true" ]
			then
				echo "Skipped $CONNECTION_ID as it is excluded in build json"
			else 
				echo "Performing substitution of any passwords in the connection $CONNECTION_ID JSON"
				TOTAL_PWD_TOKENS=$(jq -r '.package.integrations['$i'].integration.connections['$j'].connection.passwordTokens|length' $BUILD_FILE)
				if [ $TOTAL_PWD_TOKENS != "0" ]
				then
					jq -r '.package.integrations['$i'].integration.connections['$j'].connection.passwordTokens[]' $BUILD_FILE | while read z; 
					do
						
						sed -i "s/$z/${!z}/" $CONNECTION_FILE
					done
				fi	
				echo "Completed substitution of passwords in the connection $CONNECTION_ID JSON"
				echo "Updating connection $CONNECTION_ID"
				CURL_URL="$OIC_REST_BASE_URL/ic/api/integration/v1/connections/$CONNECTION_ID"
				CURL_METHOD=POST
				HTTP_RESP_CODE=$(curl -s -o /dev/null  -u "$OIC_USER:$OIC_USER_PASSWORD" -H "Content-Type:application/json" -H "X-HTTP-Method-Override:PATCH" -X "$CURL_METHOD"  -d @"$CONNECTION_FILE" -w "%{http_code}" "$CURL_URL") 
				if [ "$HTTP_RESP_CODE" != "200" ]
				then
					echo "Connection $CONNECTION_ID update returned unexpected HTTP response code $HTTP_RESP_CODE. Build Job will exit now"
					exit -1
				fi	
				echo "Connection $CONNECTION_ID updated"
			
				echo "Uploading attachments for connection $CONNECTION_ID properties"
				TOTAL_CONN_ATTACHMENTS=$(jq -r '.package.integrations['$i'].integration.connections['$j'].connection.attachments|length' $BUILD_FILE)
			
				for m in $(seq 0 $(($TOTAL_CONN_ATTACHMENTS-1))) ; 
				do
					PROPERTY_NAME=$(jq -r '.package.integrations['$i'].integration.connections['$j'].connection.attachments['$m'].attachment.propertyName' $BUILD_FILE)
					ATTACHMENT_NAME=$(jq -r '.package.integrations['$i'].integration.connections['$j'].connection.attachments['$m'].attachment.attachmentName' $BUILD_FILE)
					ATTACHMENT="Attachments/$ATTACHMENT_NAME"
					CURL_URL="$OIC_REST_BASE_URL/ic/api/integration/v1/connections/$CONNECTION_ID/attachments/$PROPERTY_NAME"
					CURL_METHOD=POST
					HTTP_RESP_CODE=$(curl -s -o /dev/null  -u "$OIC_USER:$OIC_USER_PASSWORD"   -X "$CURL_METHOD"   -F "file=@$ATTACHMENT" -w "%{http_code}" "$CURL_URL") 
					if [ "$HTTP_RESP_CODE" != "200" ]
					then
						echo "Connection $CONNECTION_ID update returned unexpected HTTP response code $HTTP_RESP_CODE. Build Job will exit now"
						exit -1
					fi	
				done
				echo "Uploaded attachments for connection $CONNECTION_ID properties"
				echo "Testing connection $CONNECTION_ID"
				CURL_URL="$OIC_REST_BASE_URL/ic/api/integration/v1/connections/$CONNECTION_ID/test"
				CURL_METHOD=POST
				HTTP_RESP_CODE=$(curl -s -o /dev/null  -u "$OIC_USER:$OIC_USER_PASSWORD" -H "Content-Type:application/json"  -X "$CURL_METHOD"  -w "%{http_code}" "$CURL_URL")
				if [ "$HTTP_RESP_CODE" != "200" ] 
				then
					echo "Connection $CONNECTION_ID testing returned unexpected HTTP response code $HTTP_RESP_CODE. Build Job will exit now"
					exit -1
				fi		
				echo "Connection $CONNECTION_ID tested successfully"
			fi
		done
		cd $HOME_DIR
		cd $BUILD_FILE_PATH
		echo "Finished update of connection properties"
		
		
		
		#update integration properties
		echo "Updating Integration Properties"
		CURL_URL="$OIC_REST_BASE_URL/ic/api/integration/v1/integrations/$INTEGRATION_ID|$INTEGRATION_VERSION"
		CURL_METHOD=POST
		HTTP_RESP_CODE=$(curl -s -o /dev/null  -u "$OIC_USER:$OIC_USER_PASSWORD" -H "Content-Type:application/json" -H "X-HTTP-Method-Override:PATCH" -X "$CURL_METHOD"  --data '{"status":"'$INTEGRATION_STATUS'", "tracingEnabledFlag":'$TRACKING_FLAG',"payloadTracingEnabledFlag":'$TRACK_PAYLOAD_FLAG'}' -w "%{http_code}" "$CURL_URL") 
		if [ "$HTTP_RESP_CODE" != "200" ]
			then
				echo "Updating integration properties returned unexpected HTTP response code $HTTP_RESP_CODE. Build Job will exit now"
				exit -1
		fi	
		echo "Integration Properties Updated"
	fi
	echo "=================================================================================================="
	echo "					COMPLETED PROCESSING INTEGRATION  $(($i+1)) of $TOTAL_INTEGRATIONS"
	echo "					$INTEGRATION_NAME $INTEGRATION_ID_$INTEGRATION_VERSION"
	echo "=================================================================================================="	
done

#import lookups
echo "Starting import of Lookups"
cd $HOME_DIR
cd Lookups/$ENVIRONMENT
TOTAL_LOOKUPS=$(jq -r '.lookups|length' $BUILD_FILE)
for k in $(seq 0 $(($TOTAL_LOOKUPS-1))) ; 
	do 
		LOOKUP_NAME=$(jq -r '.lookups['$k'].lookup.name' $BUILD_FILE)
		LOOKUP_FILE=$LOOKUP_NAME".csv"
		BUILD_EXCLUDE_FLAG=$(jq -r '.lookups['$k'].lookup.excludeFromBuild' $BUILD_FILE)
		if [ $BUILD_EXCLUDE_FLAG = "true" ]
		then
			echo "Skipped $LOOKUP_NAME as it is excluded in build json"
		else 
			echo "Performing substitution of any passwords in the Lookup $LOOKUP_NAME"
				TOTAL_PWD_TOKENS_LK=$(jq -r '.lookups['$k'].lookup.passwordTokens|length' $BUILD_FILE)
				if [ $TOTAL_PWD_TOKENS_LK != "0" ]
				then
					jq -r '.lookups['$k'].lookup.passwordTokens[]' $BUILD_FILE | while read t; 
					do
						
						sed -i "s/$t/${!t}/" $LOOKUP_FILE
					done
				fi	
			echo "Completed substitution of passwords in the Lookup $LOOKUP_NAME"
			echo "Checking if lookup $LOOKUP_NAME exits in the target environment"
			CURL_URL="$OIC_REST_BASE_URL/ic/api/integration/v1/lookups/$LOOKUP_NAME"
			CURL_METHOD=GET
			HTTP_RESP_CODE=$(curl  -s -o /dev/null -u "$OIC_USER:$OIC_USER_PASSWORD" -H "Content-Type:application/json"  -X "$CURL_METHOD"  -w "%{http_code}" "$CURL_URL") 
			if [ "$HTTP_RESP_CODE" = "404" ]
			then
			echo "Lookup $LOOKUP_NAME doesn't exist. Adding as New"
			CURL_URL="$OIC_REST_BASE_URL/ic/api/integration/v1/lookups/archive"
			CURL_METHOD=POST
			elif [ "$HTTP_RESP_CODE" = "200" ]
			then
				echo "Lookup $LOOKUP_NAME exist. Replacing it"  
				CURL_URL="$OIC_REST_BASE_URL/ic/api/integration/v1/lookups/archive"
				CURL_METHOD=PUT
			else
				echo "Lookup Exist Check returned unexpected HTTP response code $HTTP_RESP_CODE. Build Job will exit now"
				exit -1
			fi
			echo "Updating lookup $LOOKUP_NAME"
			HTTP_RESP_CODE=$(curl  -s -o /dev/null -u "$OIC_USER:$OIC_USER_PASSWORD" -X "$CURL_METHOD" -F "file=@$LOOKUP_FILE"  -w "%{http_code}" "$CURL_URL")
			if [ "$HTTP_RESP_CODE" != "200" ] && [ "$HTTP_RESP_CODE" != "204" ]
			then
				echo "Updating lookup $LOOKUP_NAME returned unexpected HTTP response code $HTTP_RESP_CODE. Build Job will exit now"
				exit -1
			fi
			echo "Updated lookup $LOOKUP_NAME"			
		fi
	done	
echo "Finished import of Lookups"
cd $HOME_DIR
cd $BUILD_FILE_PATH		



#register Libraries
echo "Starting registration of libraries"
cd $HOME_DIR
cd Libraries
TOTAL_LIBRARIES=$(jq -r '.libraries|length' $BUILD_FILE)
for x in $(seq 0 $(($TOTAL_LIBRARIES-1))) ; 
	do 
		LIBRARY_ID=$(jq -r '.libraries['$x'].library.id' $BUILD_FILE)
		LIBRARY_VERSION=$(jq -r '.libraries['$x'].library.version' $BUILD_FILE)
		LIBRARY_NAME=$(jq -r '.libraries['$x'].library.name' $BUILD_FILE)
		LIBRARY_DESC=$(jq -r '.libraries['$x'].library.description' $BUILD_FILE)
		ARCHIVE_FILE=$LIBRARY_ID"_"$LIBRARY_VERSION".jar"
		BUILD_EXCLUDE_FLAG=$(jq -r '.libraries['$x'].library.excludeFromBuild' $BUILD_FILE)
		if [ $BUILD_EXCLUDE_FLAG = "true" ]
		then
			echo "Skipped $LIBRARY_ID as it is excluded in build json"
		else 
			CURL_URL="$OIC_REST_BASE_URL/ic/api/integration/v1/libraries/archive"
			CURL_METHOD=POST
			echo "Registering Library $LIBRARY_ID"
			HTTP_RESP_CODE=$(curl  -s -o /dev/null -u "$OIC_USER:$OIC_USER_PASSWORD" -X "$CURL_METHOD" -F "file=@$ARCHIVE_FILE" -F "code=$LIBRARY_ID" -F "description=$LIBRARY_DESC" -F "code=$LIBRARY_ID"  -F "name=$LIBRARY_NAME" -F "type=API" -F "version=$LIBRARY_VERSION"  -w "%{http_code}" "$CURL_URL")
			if [ "$HTTP_RESP_CODE" != "200" ] && [ "$HTTP_RESP_CODE" != "204" ]
			then
				echo "Registering Library $LIBRARY_ID returned unexpected HTTP response code $HTTP_RESP_CODE. Build Job will exit now"
				exit -1
			fi
			echo "Registered Library $LIBRARY_ID"		
		fi
	done	
echo "Finished registration of libraries"


#clean workspace
echo "Cleaning workspace"
cd $HOME_DIR
if [ "$PK_UPLOADED" = "Y" ]
then
	
	
	cd Connections/$ENVIRONMENT/Attachments
	rm -r PRIVATE
	rm -f PRIVATE.zip
	cd $HOME_DIR
fi
rm PASSWORD
rm CUSTOM_BUILD_FILE
echo "Build Job completed"		