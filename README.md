# toolchain-to-template

The toolchain-to-template script takes a Toolchain URL and will generate an OTC Template in the current folder that when run creates a clone of you original toolchain. For example:
```
./toolchain-to-template.sh "https://cloud.ibm.com/devops/toolchains/2665ce98-ea71-43e8-b723-19bafdb7a541?env_id=ibm:yp:us-east"
```

---
### SETUP
1) The toolchain-to-template.sh script requires that the following utilities are pre-installed on your PATH: ibmcloud, curl, jq 1.6 or 1.7 (https://jqlang.github.io/jq/), and yq 4.x or 3.x or 2.x (https://github.com/mikefarah/yq) 
2) Create a temporary work folder where the script will generate your template
3) Download and copy `toolchain-to-template.sh` to your work folder
4) Determine whether your toolchain is in the public cloud or in a dedicated environment.  
   The following environments will be detected and will set PUBLIC_CLOUD=true, with other environments considered as dedicated;  
   - https://cloud.ibm.com/
   - https://test.cloud.ibm.com/
   - https://dev.console.test.cloud.ibm.com/
5) Log in to respective CLI tool:
   - For public cloud, use `ibmcloud` CLI to login to the account where your toolchain resides
   - For a dedicated environment, use `cf` CLI to log in to the account.  
     The `cf` CLI installers are at: https://github.com/cloudfoundry/cli#installers-and-compressed-binaries
6) Visit your Toolchain in the browser and copy the URL

### RUN THE SCRIPT
In a shell run the following: `./toolchain-to-template.sh https://your-toolchain-url`

The script generates a `.bluemix` folder that contains your template. To use the template, create a git repo and
copy the `.bluemix` folder into it. Commit, push and then visit your repository on an OTC Setup/Deploy page.

e.g https://cloud.ibm.com/devops/setup/deploy?env_id=ibm:yp:us-south&repository=https://your_repository_url

Note: if your repository is private:
 - on public cloud, add &repository_token=your_git_access_token
 - on dedicated, add your personal access token in an auth@, like:  
   https://console.dys0.bluemix.net/devops/setup/deploy?repository=https://some-token@github.dys0.bluemix.net/username/repo

Open the Setup/Deploy URL in a browser and click "Create" and the template will produce a newly minted clone of your original toolchain.
