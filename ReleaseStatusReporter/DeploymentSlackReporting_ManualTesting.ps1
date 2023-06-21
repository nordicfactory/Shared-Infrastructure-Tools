# Used to manually test code in DeploymentSlackReporting.ps1
. $PSScriptRoot\DeploymentSlackReporting.ps1

# Should only be used for dev scripts, comment out when running in prod
Set-StrictMode -Version Latest

# Manually set all environment variables here
# Initial pipeline environment variables
[Environment]::SetEnvironmentVariable('BUILD_BUILDID','1')
[Environment]::SetEnvironmentVariable('BUILD_SOURCEVERSIONMESSAGE','someting something Ad-302 jiberish')
[Environment]::SetEnvironmentVariable('BUILD_SOURCEVERSIONAUTHOR','AlexanderArvanitis')

# Azdo variable group variables
[Environment]::SetEnvironmentVariable('CHANNEL_ID','C04TSSPN1M3')
[Environment]::SetEnvironmentVariable('APPLICATION_NAME','Studio Api')
[Environment]::SetEnvironmentVariable('SLACK_TOKEN','xoxb-4418613869-4187544109349-0qcIQ2Xcel80caPcmK4Egqqy')

# Derived pipeline environment variables
[Environment]::SetEnvironmentVariable('JIRA_URL','')
[Environment]::SetEnvironmentVariable('AUTHOR','')
[Environment]::SetEnvironmentVariable('AVATAR','')
[Environment]::SetEnvironmentVariable('THREAD_TS','')

# Derived pipeline tag variables
[Environment]::SetEnvironmentVariable('REPORTINGJOBRESULT','SUCCEEDED')
[Environment]::SetEnvironmentVariable('DEPLOYNORTHEUJOBRESULT','SUCCEEDED')
[Environment]::SetEnvironmentVariable('DEPLOYWESTEUJOBRESULT','SUCCEEDED')
[Environment]::SetEnvironmentVariable('SWAPNORTHEUJOBRESULT','SUCCEEDED')
[Environment]::SetEnvironmentVariable('SWAPWESTEUJOBRESULT','SUCCEEDED')

ReportDeploymentStarted
