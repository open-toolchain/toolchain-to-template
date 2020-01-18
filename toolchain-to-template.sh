#!/bin/bash
# set -x
# The toolchain-to-template script takes a Toolchain URL and will generate an OTC Template that when run creates a clone
# of you original toolchain.
#
# SETUP:
# 0) These script requires that the following utilities are pre-installed on your PATH: ibmcloud, cURL, 
#    jq (https://stedolan.github.io/jq/), and yq (https://github.com/mikefarah/yq) 
# 1) Create a temporary work folder to use to generate your template
# 2) Download and copy `toolchain-to-template.sh` to your work folder
# 3) Use ibmcloud CLI to login to the account where your toolchain resides
# 4) Visit your Toolchain in the browser and copy the URL
#
# RUN THE SCRIPT
# In a shell run the following: `./toolchain-to-template.sh https://your-toolchain-url`
#
# The script generates a .bluemix folder that contains your template. To use the template create a git repo and
# copy the .bluemix folder into it. Commit, push and then visit your repository on an OTC Setup/Deploy page.
# e.g https://cloud.ibm.com/devops/setup/deploy?env_id=ibm:yp:us-south&repository=https://your_repository_url
# (Note: if your repository is private add "&repository_token=your_git_access_token")
# Open that URL in a browser and click "Create" and you will have a newly minted clone of your original toolchain

BEARER_TOKEN=

function download_classic_pipeline() {

  local PIPELINE_API_URL=$1
  local SOURCE_PIPELINE_ID=$2
  local TARGET_PIPELINE_ID=$3
  local INPUT_REPO_SERVICES_DETAILS=$4

  #local PIPELINE_API_URL="https://pipeline-service.${REGION}.devops.cloud.ibm.com/pipeline"

  echo "Get classic pipeline content: curl -H Accept: application/x-yaml ${PIPELINE_API_URL}"
  curl -s -H "Authorization: $BEARER_TOKEN" -H "Accept: application/x-yaml"  -o "${SOURCE_PIPELINE_ID}.yaml" "${PIPELINE_API_URL}"

  # echo "YAML from source classic pipeline"
  # cat "${SOURCE_PIPELINE_ID}.yaml"

  # convert the yaml to json 
  # yq r -j ${SOURCE_PIPELINE_ID}.yaml | tee ${SOURCE_PIPELINE_ID}.json
  yq r -j ${SOURCE_PIPELINE_ID}.yaml > ${SOURCE_PIPELINE_ID}.json

  # Remove the hooks and (temporary workaround) the workers definition also
  jq 'del(. | .hooks)' $SOURCE_PIPELINE_ID.json | jq 'del(.stages[] | .worker)' > "${TARGET_PIPELINE_ID}.json"

  # add the input service 
  ## Add the token url
  jq -r '.stages[] | select( .inputs and .inputs[0].type=="git") | .inputs[0].url' $SOURCE_PIPELINE_ID.json |\
  while IFS=$'\n\r' read -r input_gitrepo 
  do
    # Add a token field/line for input of type git and url being $git_repo
    cp -f $TARGET_PIPELINE_ID.json tmp-$TARGET_PIPELINE_ID.json

    INPUT_REPO_SERVICE_NAME=$( echo "${INPUT_REPO_SERVICES_DETAILS}" | grep " ${input_gitrepo}" | sed -E 's/([^ ]+) .+/\1/' )
    echo "Service $INPUT_REPO_SERVICE_NAME (refers to)-> $input_gitrepo"

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
    cp -f $TARGET_PIPELINE_ID.json tmp-$TARGET_PIPELINE_ID.json

    jq -r --arg stage_name "$stage_name" \
      '.stages[] | if ( .name==$stage_name ) then  .triggers[0]=( .triggers[0] + { "events": "{\"push\":true}" } ) else . end' \
      tmp-$TARGET_PIPELINE_ID.json \
      | jq -s '{"stages": .}' > ${TARGET_PIPELINE_ID}.json
  done

  # remove the input url
  cp -f $TARGET_PIPELINE_ID.json tmp-$TARGET_PIPELINE_ID.json
  jq -r 'del( .stages[] | select( .inputs ) | .inputs[] | select( .type == "git" ) | .url )' tmp-$TARGET_PIPELINE_ID.json > $TARGET_PIPELINE_ID.json

  # Add the pipeline properties in the target
  cp -f $TARGET_PIPELINE_ID.json tmp-$TARGET_PIPELINE_ID.json
  jq --slurpfile sourcecontent ./${SOURCE_PIPELINE_ID}.json '.stages | {"stages": ., "properties": $sourcecontent[0].properties }' ./tmp-${TARGET_PIPELINE_ID}.json > ${TARGET_PIPELINE_ID}.json

  # yq r $TARGET_PIPELINE_ID.json | tee $TARGET_PIPELINE_ID.yaml
  yq r $TARGET_PIPELINE_ID.json > $TARGET_PIPELINE_ID.yml

  echo "Classic pipeline content generated: $TARGET_PIPELINE_ID.yml"
  # echo "==="
  # cat "$TARGET_PIPELINE_ID.yml"
  # echo "==="

  # echoing the secured properties (pipeline and stage) that can not be valued there
  echo "The following pipeline secure properties needs to be updated with appropriate values:"
  jq -r '.properties[] | select(.type=="secure") | .name' ${TARGET_PIPELINE_ID}.json

  echo "The following stage secure properties needs to be updated with appropriate values:"
  jq -r '.stages[] | . as $stage | .properties // [] | .[] | select(.type=="secure") | [$stage.name] + [.name] | join(" - ")' ${TARGET_PIPELINE_ID}.json

}

function download_tekton_pipeline() {

  local PIPELINE_API_URL=$1
  local SOURCE_PIPELINE_ID=$2
  local TARGET_PIPELINE_ID=$3
  local INPUT_REPO_SERVICES_DETAILS=$4

  echo "Get tekton pipeline content: curl -H Accept: application/x-yaml ${PIPELINE_API_URL}"
  curl -s -H "Authorization: $BEARER_TOKEN" -H "Accept: application/x-yaml"  -o "${SOURCE_PIPELINE_ID}.yaml" "${PIPELINE_API_URL}"

  #echo "YAML from source tekton pipeline"
  #echo "==="
  #cat "${SOURCE_PIPELINE_ID}.yaml"
  #echo "==="

  # convert the yaml to json 
  # yq r -j ${SOURCE_PIPELINE_ID}.yaml | tee ${SOURCE_PIPELINE_ID}.json
  yq r -j ${SOURCE_PIPELINE_ID}.yaml > ${SOURCE_PIPELINE_ID}.json

  cp ${SOURCE_PIPELINE_ID}.json ${TARGET_PIPELINE_ID}.json

  # For each properties, make the type lowercase
  jq -c '.envProperties[] | .type |= ascii_downcase' ${TARGET_PIPELINE_ID}.json > properties-${TARGET_PIPELINE_ID}.json  
  # Delete envProperties in favor to properties
  cp -f $TARGET_PIPELINE_ID.json tmp-$TARGET_PIPELINE_ID.json
  jq --slurpfile props properties-${TARGET_PIPELINE_ID}.json '. | .properties=$props | del(.envProperties)' tmp-${TARGET_PIPELINE_ID}.json > ${TARGET_PIPELINE_ID}.json

  # add the input service(s) 
  jq -r '.inputs[] | select(.type=="git") | .url' $SOURCE_PIPELINE_ID.json |\
  while IFS=$'\n\r' read -r input_gitrepo 
  do
    # add service for each git input
    cp -f $TARGET_PIPELINE_ID.json tmp-$TARGET_PIPELINE_ID.json

    INPUT_REPO_SERVICE_NAME=$( echo "${INPUT_REPO_SERVICES_DETAILS}" | grep " ${input_gitrepo}" | sed -E 's/([^ ]+) .+/\1/' )
    echo "Service $INPUT_REPO_SERVICE_NAME (refers to)-> $input_gitrepo"

    # change the input url to the corresponding service reference
    jq -r -c --arg input_gitrepo "$input_gitrepo"  --arg repo_service "${INPUT_REPO_SERVICE_NAME}" \
      '.inputs[] | if ( .type=="git" and .url==$input_gitrepo) then .=( del(.url) + { "service": $repo_service }) else . end' \
      tmp-$TARGET_PIPELINE_ID.json > inputs-${TARGET_PIPELINE_ID}.json
    
    jq --slurpfile inputs inputs-${TARGET_PIPELINE_ID}.json '.inputs=$inputs' tmp-$TARGET_PIPELINE_ID.json > ${TARGET_PIPELINE_ID}.json

  done

  yq r $TARGET_PIPELINE_ID.json > $TARGET_PIPELINE_ID.yml

  echo "Tekton pipeline content generated: $TARGET_PIPELINE_ID.yml"
  #echo "==="
  #cat "$TARGET_PIPELINE_ID.yml"
  #echo "==="
}

#### MAIN ####

TOOLCHAIN_URL=$1
if [ -z "${TOOLCHAIN_URL}" ]; then 
  echo "Missing Toolchain URL argument"
  exit 1 
fi

FULL_TOOLCHAIN_URL="${TOOLCHAIN_URL}&isUIRequest=true"
echo "Toolchain url is: $FULL_TOOLCHAIN_URL"
BEARER_TOKEN=$(ibmcloud iam oauth-tokens --output JSON | jq -r '.iam_token')

OLD_TOOLCHAIN_JSON=$(curl -s \
  -H "Authorization: ${BEARER_TOKEN}" \
  -H "Accept: application/json" \
  -H "include: everything" \
  "${FULL_TOOLCHAIN_URL}")

SERVICE_BROKERS=$( echo "${OLD_TOOLCHAIN_JSON}" | jq -r '.services | { "service_brokers": . }' )
OLD_TOOLCHAIN_JSON=$( echo "${OLD_TOOLCHAIN_JSON}" | jq -r '.toolchain' )
REGION=$( echo "${OLD_TOOLCHAIN_JSON}" | jq -r '.region_id' | sed 's/.*[:]//')
# echo "SERVICE_BROKERS is: ${SERVICE_BROKERS}"
# echo "OLD_TOOLCHAIN_JSON is: ${OLD_TOOLCHAIN_JSON}"

TIMESTAMP=$(date +'%Y-%m-%dT%H-%M-%S')
WORKDIR=work-${TIMESTAMP}
mkdir $WORKDIR
cd $WORKDIR

OLD_TOOLCHAIN_JSON_FILE="tmp.old_toolchain.json"
echo "${OLD_TOOLCHAIN_JSON}" > "${OLD_TOOLCHAIN_JSON_FILE}"

TOOLCHAIN_NAME=$( echo "${OLD_TOOLCHAIN_JSON}" | jq -r '.name' )

TEMPLATE_NAME=$( echo "${OLD_TOOLCHAIN_JSON}" | jq -r '.template.name' || '' )
TOOLCHAIN_DESCRIPTION=$( echo "${OLD_TOOLCHAIN_JSON}" | jq -r '.description' || '' )

TOOLCHAIN_YML_FILE_NAME="toolchain_${TIMESTAMP}.yml"

echo "Generating ${TOOLCHAIN_YML_FILE_NAME}"
echo "version: 2" > "${TOOLCHAIN_YML_FILE_NAME}"
yq write --inplace "${TOOLCHAIN_YML_FILE_NAME}" template.name "${TEMPLATE_NAME}"
yq write --inplace "${TOOLCHAIN_YML_FILE_NAME}" template.description "${TOOLCHAIN_DESCRIPTION}"
yq write --inplace "${TOOLCHAIN_YML_FILE_NAME}" toolchain.name "${TOOLCHAIN_NAME}"

SERVICE_DETAILS=""
NEWLINE=$'\n'

# first create service details, computing service name if absent
for((i=0; 1 ;i++))
do
    # 'services[0].service_id' is like:
    # orion
    SERVICE_ID=$(yq read "${OLD_TOOLCHAIN_JSON_FILE}" "services[${i}].service_id")
    if [ 'null' = "${SERVICE_ID}"  ] ; then
        break;
    fi
    echo "Found $i: ${SERVICE_ID}"

    # 'services[0].instance_id' is like:
    # 44850da0-b5aa-4332-890c-1f8e6a48691c
    SERVICE_INSTANCE_ID=$(yq read "${OLD_TOOLCHAIN_JSON_FILE}" "services[${i}].instance_id")

    # 'services[0].toolchain_binding.name' is like:
    # webide
    SERVICE_NAME=$(yq read "${OLD_TOOLCHAIN_JSON_FILE}" "services[${i}].toolchain_binding.name")
    if [ 'null' = "${SERVICE_NAME}"  ] ; then
        PREFIX_NUM=$( echo "0${i}" | sed -E 's/0*(.*..)$/\1/' )
        SERVICE_NAME="service${PREFIX_NUM}"
    fi

    REPO_URL=$(yq read "${OLD_TOOLCHAIN_JSON_FILE}" "services[${i}].parameters.repo_url")

    SERVICE_DETAILS="${SERVICE_DETAILS}${NEWLINE}${SERVICE_INSTANCE_ID} ${SERVICE_NAME} ${REPO_URL}"
done

# echo "SERVICE_DETAILS is: ${NEWLINE}${SERVICE_DETAILS}"
# echo "SERVICE_DETAILS end"

# REPO_DETAILS lines are like ${SERVICE_NAME} ${REPO_URL}
REPO_DETAILS=$( echo "${SERVICE_DETAILS}" | grep --invert-match " null$" | sed -E 's/[^ ]+ ([^ ]+) (.+)/\1 \2/' )

# under template, add the repo services as required:
# template:
#   required:
#   - sample-repo
if [ "${REPO_DETAILS}" ] ; then
  echo "${REPO_DETAILS}" | sed -E 's/([^ ]+) .+/- \1/' \
  | yq prefix - "template.required" \
  | yq merge --inplace "${TOOLCHAIN_YML_FILE_NAME}" -
else
  echo "WARNING, no repository tool found, so not marked required, browser will give error for template with no required service."
fi

# DEBUG
#yq read "${OLD_TOOLCHAIN_JSON_FILE}"

PIPELINE_FILE_NAMES=""

for((i=0; 1 ;i++))
do
    # 'services[0].service_id' is like:
    # orion
    SERVICE_ID=$(yq read "${OLD_TOOLCHAIN_JSON_FILE}" "services[${i}].service_id")
    if [ 'null' = "${SERVICE_ID}"  ] ; then
        break;
    fi
    # echo "Found $i: ${SERVICE_ID}"
    # 'services[0].instance_id' is like:
    # 44850da0-b5aa-4332-890c-1f8e6a48691c
    SERVICE_INSTANCE_ID=$(yq read "${OLD_TOOLCHAIN_JSON_FILE}" "services[${i}].instance_id")

    # read the SERVICE_NAME from SERVICE_DETAILS - will have converted null to a value.
    SERVICE_NAME=$( echo "${SERVICE_DETAILS}" | grep "${SERVICE_INSTANCE_ID}" | sed -E 's/[^ ]+ ([^ ]+) .+/\1/' )
    # echo "Found $i: ${SERVICE_ID} ${SERVICE_NAME}"

    # 'services[0].parameters' is like:
    # container_url: ""
    # toolchain_id: e822e0f8-8e75-4420-962a-879f4f75c26b
    # dashboard_url: /devops/code/edit/edit.html#,toolchain=e822e0f8-8e75-4420-962a-879f4f75c26b
    SERVICE_PARAMETERS=$(yq read "${OLD_TOOLCHAIN_JSON_FILE}" "services[${i}].parameters")

    SERVICE_FILE_NAME="tmp.service_${i}.yml"

    # Start with service parameters list:
    echo "${SERVICE_PARAMETERS}" > "${SERVICE_FILE_NAME}"

    if [ 'pipeline' = "${SERVICE_ID}"  ] ; then
        # if pipeline, extra work
        PIPELINE_TYPE=$(echo "$SERVICE_PARAMETERS" | yq read - type)
        if [ "classic" == "$PIPELINE_TYPE" ]; then
          # if classic pipeline, extra work
          PIPELINE_EXTERNAL_API_URL=$(echo "$SERVICE_PARAMETERS" | yq read - external_api_url)
          TARGET_PIPELINE_ID="pipeline_${SERVICE_NAME}"
          download_classic_pipeline "${PIPELINE_EXTERNAL_API_URL}" "${SERVICE_INSTANCE_ID}" "${TARGET_PIPELINE_ID}" "${REPO_DETAILS}"

          PIPELINE_FILE_NAME="${TARGET_PIPELINE_ID}.yml"
          PIPELINE_FILE_NAMES="${PIPELINE_FILE_NAMES},${PIPELINE_FILE_NAME}"

          FOUND_API_KEY=$( yq read "${SERVICE_FILE_NAME}" 'configuration.env.API_KEY' )
          if [ 'null' != "${FOUND_API_KEY}" ]; then
            yq write --inplace "${SERVICE_FILE_NAME}" "configuration.env.API_KEY" ""
          fi
          FOUND_EXECUTE=$( yq read "${SERVICE_FILE_NAME}" 'configuration.execute' )
          if [ 'null' != "${FOUND_EXECUTE}" ]; then
            yq delete --inplace "${SERVICE_FILE_NAME}" "configuration.execute"
          fi
          yq delete --inplace "${SERVICE_FILE_NAME}" "configuration.content"
          yq write --inplace "${SERVICE_FILE_NAME}" "configuration.content.\$text" "${PIPELINE_FILE_NAME}"

          SERVICES_LIST=$(yq read "${PIPELINE_FILE_NAME}" 'stages[*].inputs[*].service' \
            | grep --invert-match " null$" \
            | sed -E 's/- - /- /' \
            | sort --unique )

        elif [ "tekton" == "$PIPELINE_TYPE" ]; then
          # if tekton pipeline, extra work
          SERVICE_DASHBOARD_URL=$(yq read "${OLD_TOOLCHAIN_JSON_FILE}" "services[${i}].dashboard_url")
          SERVICE_REGION_ID=$(yq read "${OLD_TOOLCHAIN_JSON_FILE}" "services[${i}].region_id")
          PIPELINE_EXTERNAL_API_URL="$(echo $TOOLCHAIN_URL | awk -F/ '{print $1"//"$3}')/${SERVICE_DASHBOARD_URL}/yaml?env_id=${SERVICE_REGION_ID}"

          TARGET_PIPELINE_ID="pipeline_${SERVICE_NAME}"

          download_tekton_pipeline "${PIPELINE_EXTERNAL_API_URL}" "${SERVICE_INSTANCE_ID}" "${TARGET_PIPELINE_ID}" "${REPO_DETAILS}"

          PIPELINE_FILE_NAME="${TARGET_PIPELINE_ID}.yml"
          PIPELINE_FILE_NAMES="${PIPELINE_FILE_NAMES},${PIPELINE_FILE_NAME}"

          SERVICES_LIST=$(yq read "${PIPELINE_FILE_NAME}" 'inputs[*].service' \
            | grep --invert-match " null$" \
            | sed -E 's/- - /- /' \
            | sort --unique )

        else
          echo "WARNING, unknown pipeline type $PIPELINE_TYPE for instance $SERVICE_INSTANCE_ID"
        fi

        # Insert services list into parameters, like:
        #   service_id: pipeline
        #   parameters:
        #     services:
        #     - sample-repo
        #     name: simple-toolchain-20191016105909826
        if [ "${SERVICES_LIST}" ] ; then
          SERVICES_LIST_FILE="tmp.${TARGET_PIPELINE_ID}_services.yml"
          echo "${SERVICES_LIST}" > "${SERVICES_LIST_FILE}"
          yq prefix --inplace "${SERVICES_LIST_FILE}" "services"
          yq merge --inplace "${SERVICE_FILE_NAME}" "${SERVICES_LIST_FILE}"
          rm "${SERVICES_LIST_FILE}"
        fi

    fi

    # suppress the value of any type:password parameter
    echo "${SERVICE_BROKERS}" |  jq -r  --arg service_id "${SERVICE_ID}" \
      '.service_brokers[] | select( .entity.unique_id == $service_id and .metadata.parameters.properties ) | .metadata.parameters.properties | keys[] | . ' |\
    while IFS=$'\n\r' read -r property_name 
    do
      PROPERTY_TYPE=$( echo "${SERVICE_BROKERS}" |  jq -r  --arg service_id "${SERVICE_ID}" --arg property_name "${property_name}" \
        '.service_brokers[] | select( .entity.unique_id == $service_id ) | .metadata.parameters.properties[$property_name] | .type' )
      if [ "${PROPERTY_TYPE}" = "password"  ] ; then
        FOUND=$( yq read "${SERVICE_FILE_NAME}" "${property_name}" )
        if [ 'null' != "${FOUND}" ]; then
          # echo "password property found: ${SERVICE_NAME} ${property_name}"
          yq write --inplace "${SERVICE_FILE_NAME}" "${property_name}" ""
        fi
      fi
    done
    if [ 'private_worker' = "${SERVICE_ID}"  ] ; then
        FOUND=$( yq read "${SERVICE_FILE_NAME}" 'workerQueueCredentials' )
        if [ 'null' != "${FOUND}" ]; then
          yq write --inplace "${SERVICE_FILE_NAME}" "workerQueueCredentials" ""
        fi
    fi
    # paranoia, other properties not declared with type: password, but repressing due to name is suspicious:
    FOUND=$( yq read "${SERVICE_FILE_NAME}" 'token' )
    if [ 'null' != "${FOUND}" ]; then
      yq write --inplace "${SERVICE_FILE_NAME}" "token" ""
    fi
    FOUND=$( yq read "${SERVICE_FILE_NAME}" 'access_token' )
    if [ 'null' != "${FOUND}" ]; then
      yq write --inplace "${SERVICE_FILE_NAME}" "access_token" ""
    fi
    FOUND=$( yq read "${SERVICE_FILE_NAME}" 'api_token' )
    if [ 'null' != "${FOUND}" ]; then
      yq write --inplace "${SERVICE_FILE_NAME}" "api_token" ""
    fi
    FOUND=$( yq read "${SERVICE_FILE_NAME}" 'password' )
    if [ 'null' != "${FOUND}" ]; then
      yq write --inplace "${SERVICE_FILE_NAME}" "password" ""
    fi

    # build these up in reverse order (parameters, then service_id, then service_name, services):
    # services:
    #   sample-build:
    #     service_id: pipeline
    #     parameters:
    #       api_url: http://pipeline-service/pipeline/pipelines/0101140f-4082-4709-9c05-5739cefa558a
    #       external_api_url: https://pipeline-service.us-east.devops.cloud.ibm.com/pipeline/pipelines/0101140f-4082-4709-9c05-5739cefa558a
    yq prefix --inplace "${SERVICE_FILE_NAME}" "parameters"
    yq write --inplace "${SERVICE_FILE_NAME}" "service_id" "${SERVICE_ID}"
    yq prefix --inplace "${SERVICE_FILE_NAME}" "${SERVICE_NAME}"
    yq prefix --inplace "${SERVICE_FILE_NAME}" "services"
    # echo " == [${i}] has: =="
    # cat "${SERVICE_FILE_NAME}"
    # echo " == /end ${i} =SERVICE_NAME="
    yq merge --inplace "${TOOLCHAIN_YML_FILE_NAME}" "${SERVICE_FILE_NAME}" 
    rm "${SERVICE_FILE_NAME}"
done

PIPELINE_FILE_NAMES=$( echo "${PIPELINE_FILE_NAMES}" | sed -E 's/,//' ) 

echo "Output ${TOOLCHAIN_YML_FILE_NAME} file."
# cat "${TOOLCHAIN_YML_FILE_NAME}"

cd ..
cat >> "README.md" << EOF
# ${TOOLCHAIN_NAME}

Generated from toolchain URL: ${TOOLCHAIN_URL}  
on ${TIMESTAMP}
EOF

mkdir -p ".bluemix"

cd ".bluemix" || exit 1

cp "../${WORKDIR}/${TOOLCHAIN_YML_FILE_NAME}" "./toolchain.yml"

echo "${PIPELINE_FILE_NAMES}" | tr "," "\n" |\
while IFS=$'\n\r' read -r pipeline_file_name 
do
  echo "Copy pipeline file: ${pipeline_file_name}"
  cp "../${WORKDIR}/${pipeline_file_name}" "."
done

cd ..
set +x
if [ -z "${DEBUG_TTT}" ]; then rm -rf ${WORKDIR} ; fi
echo "Template extraction from toolchain '${TOOLCHAIN_NAME}' done"
