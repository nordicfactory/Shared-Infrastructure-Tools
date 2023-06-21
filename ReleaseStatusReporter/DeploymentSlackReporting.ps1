$slackUpdateUrl = 'https://slack.com/api/chat.update';
$slackPostMessageUrl = 'https://slack.com/api/chat.postMessage';
# It's a bird it's a plane...
$fallbackAvatar = "https://external-preview.redd.it/FVG7tyiNZNk8dtTx5vaM1h_tVKgZuYGmnuJpmvSh2Lc.jpg?auto=webp&s=f6eea0f151f8613e2190cff6d3003e9b89431551"; 

function ReportDeploymentStarted {
    [CmdletBinding()]
    Param()
    try {
        Write-Verbose 'Calling GetGithubPersonDetails...'
        $personDetails = GetGithubPersonDetails
        Write-Verbose 'Calling GetJiraUrl...'
        $jiraUrl = GetJiraUrl
        $azdoBuildUrl = ('<https://dev.azure.com/bannerflow/Studio/_build/results?buildId={0}&view=results|{1}>' -f $env:BUILD_BUILDID, $env:BUILD_SOURCEVERSIONMESSAGE)
        Write-Verbose ('Building AzdoBuildUrl: {0}' -f $azdoBuildUrl)

        $status = 'Started :windows_loading:';
        $bodyParams = @{
            Status       = $status
            Author       = $personDetails.("Author")
            Avatar       = $personDetails.("Avatar")
            JiraUrl      = $jiraUrl
            AzdoBuildUrl = $azdoBuildUrl
        }
        Write-Verbose 'Calling BuildBody with params:' 
        Write-Verbose ($bodyParams | ConvertTo-Json -Depth 2)
        $body = BuildBody @bodyParams
        SlackPostMessage $body $slackPostMessageUrl
    }
    catch {
        Write-Error ('ReportDeploymentStarted failed to run Body: {0}' -f $body)
        Write-Host "##vso[task.complete result=Failed;]DONE"
        exit(1)
    }
}

function ReportDeploymentFinished {
    [CmdletBinding()]
    param(
        [String]$reportingStartedJobResult,
        [String]$dependantJobResults
    )
    Write-Verbose 'Environment variables:'
    Write-Verbose ('Author:                         {0}' -f $env:AUTHOR)
    Write-Verbose ('Avatar:                         {0}' -f $env:AVATAR)
    Write-Verbose ('JiraUrl:                        {0}' -f $env:JIRA_URL)
    Write-Verbose ('ThreadTS:                       {0}' -f $env:THREAD_TS)
    Write-Verbose 'Function parameters:'
    Write-Verbose ('ReportingStartedJobResult       {0}' -f $reportingStartedJobResult)
    Write-Verbose ('DependantJobResults             {0}' -f $dependantJobResults)

    try {
        $personDetails = GetGithubPersonDetails
        $jiraUrl = GetJiraUrl
        $azdoBuildUrl = ('<https://dev.azure.com/bannerflow/Studio/_build/results?buildId={0}&view=results|{1}>' -f $env:BUILD_BUILDID, $env:BUILD_SOURCEVERSIONMESSAGE)
        $status = GetOutcomeStatusMessage $dependantJobResults.Split(',')
        $bodyParams = @{
            Status       = $status
            Author       = $personDetails.("Author")
            Avatar       = $personDetails.("Avatar")
            JiraUrl      = $jiraUrl
            AzdoBuildUrl = $azdoBuildUrl
            ThreadTs     = $env:THREAD_TS
        }
        Write-Verbose 'Calling BuildBody with params:' 
        Write-Verbose ($bodyParams | ConvertTo-Json -Depth 2)
        $body = BuildBody @bodyParams
        If ([string]::IsNullOrEmpty($reportingStartedJobResult) -or $reportingStartedJobResult -ne 'Succeeded') {
            Write-Warning "ReportingStarted failed to run. Trying to repost new message."
            SlackPostMessage $body $slackPostMessageUrl 
        }
        else {
            SlackPostMessage $body $slackUpdateUrl 
        }
    }
    catch {
        try {
            Write-Warning "ReportDeploymentFinished failed. Falling back to posting generic message."
            $body = BuildSafeBody $status
            SlackPostMessage $body $slackPostMessageUrl
        }
        catch {
            Write-Error ('ReportDeploymentFinished failed Body: {0}' -f $body)
        }
    }
}

function GetGithubPersonDetails {
    [CmdletBinding()]
    Param()
    Write-Verbose 'Reading person details from environment...'
    # Firstly try to get user details from environment
    if (([string]::IsNullOrEmpty($env:AUTHOR) -eq $false) -and ([string]::IsNullOrEmpty($env:AVATAR) -eq $false)) {
        Write-Verbose ('Person details read from environment. Author: {0}, Avatar {1}' -f $env:AUTHOR, $env:AVATAR)
        $author = $env:AUTHOR
        $avatar = $env:AVATAR
    }
    else {
        Write-Verbose 'No person details found in environment. Trying to build instead.'
        $userName = ($env:BUILD_SOURCEVERSIONAUTHOR -replace '\s', '') 
        try {
            $result = Invoke-RestMethod -Uri ('https://api.github.com/users/{0}' -f $userName) -Method 'Get';
            # Get and set avat env variable
            $avatar = $result.avatar_url
            If ([string]::IsNullOrEmpty($avatar)) {
                Write-Warning ('Avatar not found, defaulting to fallback avatar {0}' -f $fallbackAvatar);
                $avatar = $fallbackImg;
            }
            else {
                Write-Verbose ('Setting variable AVATAR to {0}' -f $avatar);
                Write-Host "##vso[task.setvariable variable=AVATAR;isOutput=true]$avatar";
            }

            # Get and set author env variable
            $author = $result.name;
            If ([string]::IsNullOrEmpty($author)) {
                Write-Warning ('Name not found, falling back to userName: {0}' -f $userName)
                $author = $userName;
            }
            else {
                Write-Verbose ('Setting variable AUTHOR to {0}' -f $author)
                Write-Host "##vso[task.setvariable variable=AUTHOR;isOutput=true]$author"
            }
        }
        catch {
            Write-Warning ('Call to GitHub rest api failed with  : {0}' -f $_);
            Write-Warning ('Falling back to defaults. Author: {0}, Avatar:{1}' -f $userName, $fallbackAvatar)
            # Don't set env variable here since a later call might succeed
            $author = $userName
            $avatar = $fallbackAvatar
        }
    }

    return @{author = $author; avatar = $avatar }
}

function GetJiraUrl {
    [CmdletBinding()]
    Param()

    Write-Verbose 'Reading JiraUrl from environment...'
    # Try get Jira url from env first
    if ([string]::IsNullOrEmpty($env:JIRA_URL) -eq $false) {
        Write-Verbose ('JiraUrl read from environment: {0}' -f $env:JIRA_URL)
        return $env:JIRA_URL
    }
    else {
        Write-Verbose 'No JiraUrl found in environment. Trying to build instead.'
        $jiraUrlTemplate = '<https://bannerflow.atlassian.net/browse/{0}|https://bannerflow.atlassian.net/browse/{0}>';
        $jiraFallbackUrlTemplate = '<https://bannerflow.atlassian.net/issues/?jql=text%20~%20%22{0}%22|Jira not found, search here.>';
        # Broader regex is used to find most common variants of jira misspellings
        $broadFindJiraRegex = '[a-zA-Z]{2,4}.[0-9]{2,4}'
        $narrowFindJiraRegex = '[a-zA-Z]{2,4}-[0-9]{2,4}'

        if ($env:BUILD_SOURCEVERSIONMESSAGE -match $broadFindJiraRegex) {
            $matchedJira = $matches[0].Trim();
                
            if ($matchedJira -match $narrowFindJiraRegex) {
                $jiraUrl = ($jiraUrlTemplate -f $matchedJira)
                Write-Verbose ('Setting variable JIRA_URL to {0}' -f $jiraUrl);
                Write-Host "##vso[task.setvariable variable=JIRA_URL;isOutput=true]$jiraUrl";
            }
            else {
                # Try fixing jira
                #TODO only fixes cases like ABC123
                $jiraParts = $jira -split ('(?=\d)'), 2;
                $potentiallyFixedJira = ("{0}-{1}" -f $jiraParts[0], $jiraParts[1])
                if ($potentiallyFixedJira -match $narrowFindJiraRegex) {
                    $jiraUrl = ($jiraUrlTemplate -f $potentiallyFixedJira)
                    Write-Verbose ('Setting variable JIRA_URL to {0}' -f $jiraUrl);
                    Write-Host "##vso[task.setvariable variable=JIRA_URL;isOutput=true]$jiraUrl";    
                }
                else {
                    $jiraUrl = ($jiraFallbackUrlTemplate -f $matchedJira)
                    Write-Warning ('Not able to interpret jira from branch/message. Defaulting to backup. PotentiallyMatchedJira: {0}' -f $jiraUrl);
                }
            }    
        }
        else { 
            $jiraUrl = ($jiraFallbackUrlTemplate -f $env:BUILD_SOURCEVERSIONMESSAGE)
            Write-Warning ("Not able to interpret jira from branch/message. Defaulting to backup. JiraUrl: {0}" -f $jiraUrl);
        }
        return $jiraUrl;
    }
}

function BuildBody {
    [CmdletBinding()]
    param(
        [System.String]$status,
        [System.String]$author,
        [System.String]$avatar,
        [System.String]$jiraUrl,
        [System.String]$azdoBuildUrl,
        [System.String]$threadTs
    )
    $body = @{
        channel  = "$($env:CHANNEL_ID)"
        username = "$author (automated)"
        icon_url = "$avatar"
        blocks   = @(
            @{
                type = 'divider'
            },
            @{
                type = 'header'
                text = @{
                    type = 'plain_text'
                    text = "$env:APPLICATION_NAME releasing to Production :deployparrot:"
                }
            },
            @{
                type = 'section'
                text = @{
                    type = 'mrkdwn'
                    text = "*Build:*\n$azdoBuildUrl"
                }
            },
            @{
                type = 'section'
                text = @{
                    type = 'mrkdwn'
                    text = "*Jira:*\n$jiraUrl"
                }
            },
            @{
                type = 'section'
                text = @{
                    type = 'mrkdwn'
                    text = "*Status:*\n$status"
                }
            },
            @{
                type = 'divider'
            }
        ) 
    }
    if ([string]::IsNullOrEmpty($threadTs) -eq $false) {
        $body.ts = $threadts
    } 

    Write-Verbose 'Built body:' 
    Write-Verbose ($body | ConvertTo-Json -Depth 4)
    return $body | ConvertTo-Json -depth 4 | Foreach-Object { [System.Text.RegularExpressions.Regex]::Unescape($_) } 
}

function BuildSafeBody {
    [CmdletBinding()]
    param([String]$status)

    $text = ('{0} releasing to production. BuildId: {1}, BuildSourceVersion: {2}, Status: {3}' -f $env:APPLICATION_NAME, $env:BUILD_BUILDID, $env:BUILD_SOURCEVERSIONMESSAGE, $status);
    $body = @{
        channel  = $env:CHANNEL_ID
        text     = $text
        username = "$env:BUILD_SOURCEVERSIONAUTHOR (automated)"
        icon_url = $fallbackAvatar
    }
    Write-Verbose 'Built body:' 
    Write-Verbose ($body | ConvertTo-Json -Depth 2)
    return $body | ConvertTo-Json -depth 2 | Foreach-Object { [System.Text.RegularExpressions.Regex]::Unescape($_) };
}

function SlackPostMessage {
    [CmdletBinding()]
    param(
        [string]$body,
        [string]$slackUrl
    )

    # Validate and read from pipeline variables
    If ([string]::IsNullOrEmpty($env:SLACK_TOKEN)) {
        Write-Warning 'Mandatory variable SLACK_TOKEN is empty. Exiting'
        Write-Host "##vso[task.complete result=Failed;]DONE"
        exit(1)
    }
    If ([string]::IsNullOrEmpty($env:CHANNEL_ID)) {
        Write-Warning 'Mandatory variable CHANNEL_ID is empty. Exiting' 
        Write-Host "##vso[task.complete result=Failed;]DONE"
        exit(1)
    }

    Write-Verbose ('Calling {0} for thread: {1}' -f $slackUrl, $env:THREAD_TS)
    try {

        $response = Invoke-RestMethod -Uri $slackUrl -ContentType 'application/json' -Headers @{Authorization = "Bearer $env:SLACK_TOKEN" } -Method 'POST' -Body $body
        
        If ($response.ok -ne $true) {
            Write-Error $response.Error
            throw
        }
        
        If ([string]::IsNullOrEmpty($env:THREAD_TS)) {
            $thread_ts = $response.ts;
            Write-Verbose "Setting variable THREAD_TS to $thread_ts";
            Write-Host "##vso[task.setvariable variable=THREAD_TS;isOutput=true]$thread_ts";
        }
    }
    catch {
        Write-Error "Call to Slack rest api failed with  : $_ | $($_.ScriptStackTrace)"
        Write-Warning $body
        throw
    }
}

function GetOutcomeStatusMessage {
    [CmdletBinding()]
    param(
        [String[]]$dependantJobResults
    )

    # If ALL stages succeeded
    If ($dependantJobResults.Contains('Succeeded') -and @($dependantJobResults | Select-Object -Unique).Count -eq 1 ) { 
        $statusMessage = 'Succeeded :white_check_mark:'; 
    }

    # Else if ANY failed
    ElseIf ($dependantJobResults.Where({ $_ -eq 'Failed' }, 'First').Count -gt 0) {
        $statusMessage = 'Failed :x:'
    }
    ElseIf ($dependantJobResults.Where({ $_ -eq 'Skipped' }, 'First').Count -gt 0) {
        $statusMessage = 'Skipped :x:'
    }
    ElseIf ($dependantJobResults.Where({ $_ -eq 'Canceled' }, 'First').Count -gt 0) {
        $statusMessage = 'Canceled :x:'
    }
    ElseIf ($dependantJobResults.Where({ $_ -eq 'SucceededWithIssues' }, 'First').Count -gt 0) {
        $statusMessage = 'SucceededWithIssues :white_check_mark::alphabet_yellow_exclamation:'
    }
    return $statusMessage;
}

function Report {
    [CmdletBinding()]
    param(
        [ValidateSet('Started', 'Finished')]
        [System.String]$action,
        [string]$reportingStartedJobResult,
        [String]$dependantJobResults
    )
    Write-Verbose 'Environment variables:'
    Write-Verbose ('ApplicationName:                {0}' -f $env:APPLICATION_NAME)
    Write-Verbose 'Function parameters:'
    Write-Verbose ('Action                          {0}' -f $action)
    If ($action -eq 'Started') {
        Write-Verbose 'Calling method ReportDeploymentStarted'
        ReportDeploymentStarted  
    }
    elseif ($action -eq 'Finished') {
        ReportDeploymentFinished $reportingStartedJobResult $dependantJobResults
    }
    else {
        Write-Warning ('No valid action passed. Action: {0}' -f $action)
        Write-Host "##vso[task.complete result=Failed;]DONE"
    }
}

Report @args