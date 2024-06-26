

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
