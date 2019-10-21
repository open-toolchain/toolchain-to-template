# toolchain-to-template

- log in to ibmcloud on the command line
- ensure you have targeted a region (if none chosen by default: ibmcloud target -r us-south )
- download the 2 scripts; export.sh and download_pipeline.sh
- note, it generates many temporary files - put your scripts into a folder to contain the temporary files
- find a toolchain guid on the same region you've connected on the command line
  that is, open the toolchain in a browser and copy the id from the url
- export TOOLCHAIN_ID=<your-guid>
- It requires cURL, 
- jq (https://stedolan.github.io/jq/) 
- yq (https://github.com/mikefarah/yq)
- chmod u+x export.sh
- chmod u+x download_pipleine.sh
- ./export.sh

- verify it generated a folder toolchain-<datestamp>/.bluemix folder with a toolchain.yml file and pipeline_*.yml files

- create a new git repo, check in the .bluemix folders and files into the new git repo (can be private, but would need a token to access).

- Compose a URL to the setup/deploy page:
 https://cloud.ibm.com/devops/setup/deploy?repository=https://us-south.git.cloud.ibm.com/myrepo/try-from-toolchain-generated&env_id=ibm:yp:us-south&repository_token=some-token

- open that, click Create.

