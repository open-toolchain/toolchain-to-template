#!/bin/bash
# uncomment to debug the script
# set -x
# This script is called by the export.sh script. 
# This script does a download of a pipeline
# It requires cURL, jq (https://stedolan.github.io/jq/) and yq (https://github.com/mikefarah/yq) available
# You must be logged-in to the account and the region that the toolchain/pipelines you want to duplicate from/to
# are hosted

BEARER_TOKEN=$(ibmcloud iam oauth-tokens | grep "IAM token" | sed 's/^IAM token:[ ]*//')

REGION=$(ibmcloud target | grep -i region: | awk '{print $2};')

# PIPELINE_API_URL="https://devops-api.$REGION.bluemix.net/v1/pipeline"
# urls like https://pipeline-service.us-south.devops.cloud.ibm.com/pipeline/pipelines/0101140f-4082-4709-9c05-5739cefa558a
PIPELINE_API_URL="https://pipeline-service.${REGION}.devops.cloud.ibm.com/pipeline"

if [ -z "$SOURCE_PIPELINE_ID" ]; then
  echo "Source pipeline not defined"
  exit 1
fi

if [ -z "$TARGET_PIPELINE_ID" ]; then
  echo "Target pipeline not defined"
  exit 1
fi

if [ -z "$INPUT_REPO_SERVICES_DETAILS" ]; then
  echo "Input repo services details not defined"
  exit 1
fi

# echo "SOURCE_PIPELINE_ID is: ${SOURCE_PIPELINE_ID}"
# echo "TARGET_PIPELINE_ID is: ${TARGET_PIPELINE_ID}"
# echo "INPUT_REPO_SERVICE_NAME is: ${INPUT_REPO_SERVICE_NAME}"

echo "about to do: curl -H Accept: application/x-yaml ${PIPELINE_API_URL}/pipelines/${SOURCE_PIPELINE_ID}"
curl -H "Authorization: $BEARER_TOKEN" -H "Accept: application/x-yaml"  -o "${SOURCE_PIPELINE_ID}.yaml" "${PIPELINE_API_URL}/pipelines/${SOURCE_PIPELINE_ID}"

# echo "YAML from source pipeline"
# cat "${SOURCE_PIPELINE_ID}.yaml"

# Find the token url for the git tile
# echo "about to get: ${PIPELINE_API_URL}/pipelines/${SOURCE_PIPELINE_ID}/inputsources"
# curl -H "Authorization: $BEARER_TOKEN" -H "Content-Type: application/json" -o "${SOURCE_PIPELINE_ID}_inputsources.json" "${PIPELINE_API_URL}/pipelines/${SOURCE_PIPELINE_ID}/inputsources"

# convert the yaml to json 
# yq r -j ${SOURCE_PIPELINE_ID}.yaml | tee ${SOURCE_PIPELINE_ID}.json
yq r -j ${SOURCE_PIPELINE_ID}.yaml > ${SOURCE_PIPELINE_ID}.json

# Remove the hooks and (temporary workaround) the workers definition also
jq 'del(. | .hooks)' $SOURCE_PIPELINE_ID.json | jq 'del(.stages[] | .worker)' > "${TARGET_PIPELINE_ID}.json"

# add the input service 
## Add the token url
jq -r '.stages[] | select( .inputs[0].type=="git") | .inputs[0].url' $SOURCE_PIPELINE_ID.json |\
while IFS=$'\n\r' read -r input_gitrepo 
do
  # token_url=$(cat "${SOURCE_PIPELINE_ID}_inputsources.json" | jq -r --arg git_repo "$input_gitrepo" '.[] | select( .repo_url==$git_repo ) | .token_url')
  # echo "token url: $input_gitrepo => $token_url"

  # Add a token field/line for input of type git and url being $git_repo
  cp -f $TARGET_PIPELINE_ID.json tmp-$TARGET_PIPELINE_ID.json

  INPUT_REPO_SERVICE_NAME=$( echo "${INPUT_REPO_SERVICES_DETAILS}" | grep " ${input_gitrepo}" | sed -E 's/([^ ]+) .+/\1/' )
  echo "service for repo url: $INPUT_REPO_SERVICE_NAME : $input_gitrepo"

    # '.stages[] | if ( .inputs[0].type=="git" and .inputs[0].url==$input_gitrepo) then  .inputs[0]=(.inputs[0] + { "service": $repo_service }) else . end' \
  jq -r --arg input_gitrepo "$input_gitrepo"  --arg repo_service "${INPUT_REPO_SERVICE_NAME}" \
    '.stages[] | if ( .inputs[0].type=="git" and .inputs[0].url==$input_gitrepo) then  .inputs[0]=( .inputs[0] + { "service": $repo_service }) else . end' \
    tmp-$TARGET_PIPELINE_ID.json \
    | jq -s '{"stages": .}' > ${TARGET_PIPELINE_ID}.json
done

# convert:
# stages:
# - name: BUILD
#   triggers:
#   - events: null
#     type: git
# to have:
#   - events: '{"push":true}'

jq -r '.stages[] | select( .triggers[0].type=="git" and .triggers[0].events == null ) | .name ' $SOURCE_PIPELINE_ID.json |\
while IFS=$'\n\r' read -r stage_name 
do
  # token_url=$(cat "${SOURCE_PIPELINE_ID}_inputsources.json" | jq -r --arg git_repo "$input_gitrepo" '.[] | select( .repo_url==$git_repo ) | .token_url')
  # echo "token url: $input_gitrepo => $token_url"

  # Add a token field/line for input of type git and url being $git_repo
  cp -f $TARGET_PIPELINE_ID.json tmp-$TARGET_PIPELINE_ID.json

  INPUT_REPO_SERVICE_NAME=$( echo "${INPUT_REPO_SERVICES_DETAILS}" | grep " ${input_gitrepo}" | sed -E 's/([^ ]+) .+/\1/' )
  echo "service for repo url: $INPUT_REPO_SERVICE_NAME : $input_gitrepo"

  jq -r --arg stage_name "$stage_name" \
    '.stages[] | if ( .name==$stage_name ) then  .triggers[0]=( .triggers[0] + { "events": "{\"push\":true}" } ) else . end' \
    tmp-$TARGET_PIPELINE_ID.json \
    | jq -s '{"stages": .}' > ${TARGET_PIPELINE_ID}.json
done



# remove the input url
cp -f $TARGET_PIPELINE_ID.json tmp-$TARGET_PIPELINE_ID.json
jq -r 'del( .stages[] | .inputs[] | select( .type == "git" ) | .url )' tmp-$TARGET_PIPELINE_ID.json > $TARGET_PIPELINE_ID.json

# Add the pipeline properties in the target
cp -f $TARGET_PIPELINE_ID.json tmp-$TARGET_PIPELINE_ID.json
jq --slurpfile sourcecontent ./${SOURCE_PIPELINE_ID}.json '.stages | {"stages": ., "properties": $sourcecontent[0].properties }' ./tmp-${TARGET_PIPELINE_ID}.json > ${TARGET_PIPELINE_ID}.json

# yq r $TARGET_PIPELINE_ID.json | tee $TARGET_PIPELINE_ID.yaml
yq r $TARGET_PIPELINE_ID.json > $TARGET_PIPELINE_ID.yml

echo "$TARGET_PIPELINE_ID.yml generated"
# echo "==="
# cat "$TARGET_PIPELINE_ID.yml"
# echo "==="

# Include the yaml as rawcontent (ie needs to replace cr by \n and " by \" )
# echo '{}' | jq --rawfile yaml $TARGET_PIPELINE_ID.yaml '{"config": {"format": "yaml","content": $yaml}}' > ${TARGET_PIPELINE_ID}_configuration.json

# # HTTP PUT to target pipeline
# curl -is -H "Authorization: $BEARER_TOKEN" -H "Content-Type: application/json" -X PUT -d @${TARGET_PIPELINE_ID}_configuration.json $PIPELINE_API_URL/pipelines/$TARGET_PIPELINE_ID/configuration 

# Check the configuration if it has been applied correctly
# curl -H "Authorization: $BEARER_TOKEN" -H "Accept: application/json" $PIPELINE_API_URL/pipelines/$TARGET_PIPELINE_ID/configuration

# echoing the secured properties (pipeline and stage) that can not be valued there
echo "The following pipeline secure properties needs to be updated with appropriate values:"
jq -r '.properties[] | select(.type=="secure") | .name' ${TARGET_PIPELINE_ID}.json

echo "The following stage secure properties needs to be updated with appropriate values:"
jq -r '.stages[] | . as $stage | .properties // [] | .[] | select(.type=="secure") | [$stage.name] + [.name] | join(" - ")' ${TARGET_PIPELINE_ID}.json


# echo "doing exit 1"
# exit 1
