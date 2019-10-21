#!/bin/bash

# To use this script:
# - log in to ibmcloud on the command line
# - ensure you have targeted a region (if none chosen by default: ibmcloud target -r us-south )
# - download the 2 scripts; export.sh and download_pipeline.sh
# - note, it generates many temporary files - put your scripts into a folder to contain the temporary files
# - find a toolchain guid on the same region you've connected on the command line
#   that is, open the toolchain in a browser and copy the id from the url
# - export TOOLCHAIN_ID=<your-guid>
# - It requires cURL, 
# - jq (https://stedolan.github.io/jq/) 
# - yq (https://github.com/mikefarah/yq)
# - chmod u+x export.sh
# - chmod u+x download_pipleine.sh
# - ./export.sh
# - verify it generated a folder toolchain-<datestamp>/.bluemix folder with a toolchain.yml file and pipeline_*.yml files
# - create a new git repo, check in the .bluemix folders and files into the new git repo (can be private, but would need a token to access).
# - Compose a URL to the setup/deploy page:
#  https://cloud.ibm.com/devops/setup/deploy?repository=https://us-south.git.cloud.ibm.com/myrepo/try-from-toolchain-generated&env_id=ibm:yp:us-south&repository_token=some-token
# - open that, click Create.


token=$(ibmcloud iam oauth-tokens | head -1 | sed 's/.*:[ \t]*//')
# api_key=$(ibmcloud iam api-key-create "api-key created on $(date)" | grep "API Key" | sed 's/API Key[ ]*\([^ ]*\)[ ]*/\1/g')
# resource_group_id=$(ibmcloud resource groups --output json | jq -r '.[0].id')
# org_name=$(ibmcloud cf t | grep org | sed 's/org\:[ ]*//g')
# space_name=$(ibmcloud cf t | grep space | sed 's/space\:[ ]*//g')
prod_region=$(ibmcloud target | grep Region | sed -E 's/.+:[ ]*([^ ]*)[ ]*/\1/g'  | sed -E 's/(.+)/ibm:yp:\1/g')

host="https://cloud.ibm.com"

# env_id="ibm:yp:us-south"
#env_id="ibm:yp:eu-de"
# env_id="ibm:yp:us-east"
env_id="${prod_region}"

if [ -z "${TOOLCHAIN_ID}" ]; then 
  # TOOLCHAIN_ID="35cec4f7-d7a3-4bf0-b249-73668fb3bb22"
  echo "TOOLCHAIN_ID not detected"
  exit 1 
fi

if [ -z "${prod_region}" ]; then 
  echo "Region not detected"
  exit 1 
fi


url="${host}/devops/toolchains/${TOOLCHAIN_ID}?env_id=${env_id}"

echo "Toolchain url is: $url"

OLD_TOOLCHAIN_JSON=$(curl \
  -H "Authorization: ${token}" \
  -H "Accept: application/json" \
  -H "include: everything" \
  "${url}")

OLD_TOOLCHAIN_JSON_FILE="tmp.old_toolchain.json"
echo "${OLD_TOOLCHAIN_JSON}" > "${OLD_TOOLCHAIN_JSON_FILE}"

TOOLCHAIN_NAME=$( echo "${OLD_TOOLCHAIN_JSON}" | jq -r '.name' )
TEMPLATE_NAME=$( echo "${OLD_TOOLCHAIN_JSON}" | jq -r '.template.name' || '' )
TOOLCHAIN_DESCRIPTION=$( echo "${OLD_TOOLCHAIN_JSON}" | jq -r '.description' || '' )

TIMESTAMP=$(date +'%Y-%m-%dT%H-%M-%S')
TOOLCHAIN_YML_FILE_NAME="toolchain_${TIMESTAMP}.yml"

echo "about to generate ${TOOLCHAIN_YML_FILE_NAME}"
cat >> "${TOOLCHAIN_YML_FILE_NAME}" << EOF
version: '2'
template:
  name: '${TEMPLATE_NAME}'
  description: '${TOOLCHAIN_DESCRIPTION}'
toolchain:
  name: '${TOOLCHAIN_NAME}'
EOF

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
        SERVICE_NAME="${SERVICE_ID}${i}"
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
echo "${REPO_DETAILS}" | sed -E 's/([^ ]+) .+/- \1/' \
 | yq prefix - "template.required" \
 | yq merge --inplace "${TOOLCHAIN_YML_FILE_NAME}" -

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
        export SOURCE_PIPELINE_ID="${SERVICE_INSTANCE_ID}"
        export TARGET_PIPELINE_ID="pipeline_${SERVICE_NAME}"
        export INPUT_REPO_SERVICES_DETAILS="${REPO_DETAILS}"

        ./download_pipeline.sh

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

        # Insert services list into parameters, like:
        #   service_id: pipeline
        #   parameters:
        #     services:
        #     - sample-repo
        #     name: simple-toolchain-20191016105909826
        SERVICES_LIST_FILE="tmp.${TARGET_PIPELINE_ID}_services.yml"
        yq read "${PIPELINE_FILE_NAME}" 'stages[*].inputs[*].service' \
          | grep --invert-match " null$" \
          | sed -E 's/- - /- /' \
          > "${SERVICES_LIST_FILE}"
        yq prefix --inplace "${SERVICES_LIST_FILE}" "services"
        yq merge --inplace "${SERVICE_FILE_NAME}" "${SERVICES_LIST_FILE}"
        rm "${SERVICES_LIST_FILE}"
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

mkdir "toolchain-${TIMESTAMP}"
cd "toolchain-${TIMESTAMP}" || exit 1

cat >> "README.md" << EOF
# ${TOOLCHAIN_NAME}

Generated from toolchain id: ${TOOLCHAIN_ID}  
on ${TIMESTAMP}
EOF

mkdir ".bluemix"

cd ".bluemix" || exit 1

cp "../../${TOOLCHAIN_YML_FILE_NAME}" "./toolchain.yml"

echo "${PIPELINE_FILE_NAMES}" | tr "," "\n" |\
while IFS=$'\n\r' read -r pipeline_file_name 
do
  echo "copy pipeline file: ${pipeline_file_name}"
  cp "../../${pipeline_file_name}" "."
done

cd ..
cd ..

echo "done - output in folder toolchain-${TIMESTAMP}"
