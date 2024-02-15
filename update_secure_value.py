import os
import json
import ibmcloud
import requests
import yaml
import ruamel.yaml
import argparse

"""
The fetchPipelineValues method fetches pipeline details and places secret refernces of the pipeline in config of that pipeline generated by toolchain-to-template.sh
@param pipline_ID : is a string representing id of the pipeline
@param file_name : is a string representing config file name of the pipeline
"""
def fetchPipelineValues(pipline_ID,file_name):
   data= ibmcloud.getPipelineInfo(pipline_ID,"tekton")
   data= json.loads(data)
   envProperties= data["envProperties"]
   triggers= data["triggers"]

   config, ind, bsi = ruamel.yaml.util.load_yaml_guess_indent(open(file_name))
   config_properties = config['properties']
   for envProps in envProperties:
      for configProps in config_properties:
          if envProps["type"]=="SECURE":
            if not isHardCoded(envProps["value"]):
             if configProps["name"]== envProps["name"]:
                configProps["value"] = envProps["value"]
   
   config_triggers = config['triggers']

   for trigger in triggers:
      for configtrigger in config_triggers:
          if trigger["name"]== configtrigger["name"]:
             config_trigger_props= configtrigger["properties"]
             trigger_props= trigger["properties"]
             for t_prop in trigger_props:
               for c_prop in config_trigger_props:
                  if t_prop["type"]=="SECURE":
                   if not isHardCoded(t_prop["value"]):
                     if t_prop["name"]== c_prop["name"]:
                        c_prop["value"] = t_prop["value"]

   yaml = ruamel.yaml.YAML()
   yaml.indent(mapping=6, sequence=4) 
   with open(file_name, 'w') as fp:
      yaml.dump(config, fp)
      fp.close()  

""" 
The isHardCoded function check whether the secret value passed is hardcoded or secret reference
@param value: is a string representing secret value
@return flag : is a boolean which is true if the secret is hardcoded
"""
def isHardCoded(value):
    flag= True
    if not value or value == "":
        flag= False
    vaultPrefix="{vault::"
    if type(value)==str and value.startswith(vaultPrefix):
        flag= False
    elif type(value)==str and value.startswith('crn:'):
       flag= False
    return flag
       
"""
Execution Start Point
"""
if __name__ == "__main__":
    arg_parser = argparse.ArgumentParser(description="To run commands on given worker")
    arg_parser.add_argument('pipelineId', help=" ")
    arg_parser.add_argument('fileName', help=" ")
    args = arg_parser.parse_args()
    fetchPipelineValues(args.pipelineId, args.fileName)


