

import logging
import shlex
import subprocess
import time
import json
import requests
import base64
import os
from datetime import datetime

MAX_RETRIES=5

git_url = "https://github.ibm.com/api/v3"
# Logs the given message using logging.
def log(msg=""):
    logging.getLogger("cat").info(msg=msg)

# Execute the given bash command. 
# The command parameter can either be a string or an array of strings where each entry is an argument.
# If the command fails, sleep 10s and retries as many times as specified by maxTries.
# Raises a CalledProcessError if the command still fails after the given retries.
# Log the command if outputCommand is set to True (default)
# Log the output of the command if outputResult is set to True (default)
# Return the output of the command
def execute(command, maxTries=1, outputCommand=True, outputResult=True):
    failures = 0
    if type(command) is list:
      args=command
    else:
      args=shlex.split(command)
    while True:
        try:
            if outputCommand:
                log(command)
            result = subprocess.check_output(args, cwd=None, stderr=subprocess.STDOUT, input=None).decode("utf-8")
            if outputResult:
                log(result)
            return result
        except subprocess.CalledProcessError as e:
            failures = failures + 1
            if maxTries == failures:
              if outputResult:
                  log(e.output)
                  log(e.stdout.decode('utf-8'))
              raise e
            time.sleep(10)

# Helper (not API) to log the output of the given exception, then log the given message, then raise the exception.
def _logAndRaise(e, msg):
    log(e.output)
    log()
    log(msg)
    raise e

# Get the information of the given pipeline.
# The pipelineId (string) is the id of the pipeline.
# The pipelineType (string) is either "tekton" or "classic"
# Return the json (string) returned by `ibmcloud dev tekton-info` or `ibmcloud dev pipeline-get`.
# Raise a CalledProcessError if the pipeline info cannot be retrieved.
def getPipelineInfo(pipelineId, pipelineType):
    if pipelineType == "tekton":
        getPipeline = "tekton-info"
    else:
        getPipeline = "pipeline-get"
    command="ibmcloud dev " + getPipeline + " " + pipelineId + " --output JSON"
    try:
        return execute(command, maxTries=MAX_RETRIES, outputCommand=False, outputResult=False)
    except subprocess.CalledProcessError as e:
        _logAndRaise(e, "Failed to run: " + command)



# Pushed the modified file to git using ghToken
# org (string) is the organization id of git repository
# repo (string) is the git repository name
# filename (string) is the name of the file to be pushed to git. can contain the path if the file resides in a folder
# branch (string) is the name of the branch to push the file
# githubToken (string) is the github token
# msg (string) is the commit message
# localFilePath (string) is the path to the updated file that you have in local.
# Example inputs:
#   pushToGithub("org-ids","key-rotation","name of the file", "new branch name","12345","commit message")
# Expected output:
#   Returns the http response in case of success
#   Returns None in case of failure
def pushToGithub(org,repo,fileName, branch, githubToken,msg,localFilePath):
    print(f"\nStarted pushing {localFilePath} to {org}/{repo}/{fileName} in branch {branch}")

    headers = {"Accept": "application/vnd.github.v3+json", "Authorization": "token "+githubToken}
    segments=fileName.split('/')
    if segments[0] == '.':
        parentSegments=segments[1:-1]
    else:
        parentSegments=segments[:-1] 
    parent='/'.join(parentSegments)
    parentUrl = f"{git_url}/repos/{org}/{repo}/git/trees/{branch}:{parent}"
    parentResponse = requests.get(parentUrl+'?ref='+branch, headers = headers)
    if parentResponse.ok or parentResponse.status_code == 404:
        parentData = parentResponse.json()
        simpleName=fileName.split('/')[-1]
        file = None
        for fileData in parentData.get('tree', []):
            if fileData['path'] == simpleName:
                file = fileData
                break
        with open(localFilePath, 'rb') as f:
            base64content=base64.b64encode(f.read())
        url = git_url + "/repos/"+org+"/"+repo+"/contents/"+fileName
        if file:
            blobUrl = file['url']
            blobResp = requests.get(blobUrl, headers = headers)
            if blobResp.ok:
                blob = blobResp.json()
                localFileContent = base64content.decode('utf-8')
                remoteFileContent = blob['content'].replace('\n', '')
                if localFileContent != remoteFileContent:
                    data = json.dumps({"message":msg,
                                        "branch": branch,
                                        "content": base64content.decode("utf-8") ,
                                        "sha": file['sha']
                                        })
                    resp = requests.put(url, data, headers = headers)
                    if resp.ok:
                        print(f"\nUpdating {org}/{repo}/{fileName} was successful")
                        result = resp.json()
                        return result
                    else: 
                        print(f"\nError while updating {org}/{repo}/{fileName} in branch {branch}")
                        print(f"Response: {resp.json()}")
                        return None
                else:
                    print(f"\nNo changes to {org}/{repo}/{fileName} in branch {branch}")
                    return blobResp.json()
            else:
                print(f"\nError while getting {blobUrl}")
                print(f"Response: {blobResp.json()}")
                return None
        else:
            # file not found, create it
            data = json.dumps({"message":msg,
                                "branch": branch,
                                "content": base64content.decode("utf-8") ,
                                })
            resp = requests.put(url, data, headers = headers)
            if resp.ok:
                print(f"\nCreating {org}/{repo}/{fileName} was successful")
                result = resp.json()
                return result
            else: 
                print(f"\nError while creating {org}/{repo}/{fileName} in branch {branch}")
                print(f"Response: {resp.json()}")
                return None
    else:
        print(f"\nError while getting {parentUrl}")
        print(f"Response: {parentResponse.json()}")
        return None
 
