import os 
import common_functions

"""
This method is used to push all the files places in .bluemix folder to github
file_org_repo: set org_name/repo_name in env variable file_org_repo
file_branch: set file_branch to the branch name
github-token: set github-token 
"""
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