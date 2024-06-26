import os 
import common_functions

def pushFilesToGit():
    filesList = os.listdir(".bluemix")
    file_org_repo=os.environ.get("file_org_repo")
    output={}
    for file in filesList:
      res=common_functions.pushToGithub(file_org_repo.split("/")[0],file_org_repo.split("/")[1],".bluemix"+"/"+file, os.environ.get("file_branch"),os.environ.get("github-token") ,"",".bluemix"+"/"+file)
      output[file]=res
    return output

if __name__ == "__main__":
   pushFilesToGit()