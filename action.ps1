#------------------------------------------------------------------------------
# FILE:         action.ps1
# CONTRIBUTOR:  Jeff Lill
# COPYRIGHT:    Copyright (c) 2005-2021 by neonFORGE LLC.  All rights reserved.
#
# The contents of this repository are for private use by neonFORGE, LLC. and may not be
# divulged or used for any purpose by other organizations or individuals without a
# formal written and signed agreement with neonFORGE, LLC.

#------------------------------------------------------------------------------
# Sends a build related notification to a Teams channel.
#
# INPUTS:
#
#   channel         - Target Teams channel webhook URI
#   operation       - Identifies what's being built
#   start-time      - Time when the build started (formatted like YYYY-MM-DD HH-MM:SSZ)
#   finish-time     - Time when the build completed (formatted like YYYY-MM-DD HH-MM:SSZ)
#   build-outcome   - Build step outcome, one of: 'success', 'failure', 'cancelled', or 'skipped'
    
# Verify that we're running on a properly configured neonFORGE jobrunner 
# and import the deployment and action scripts from neonCLOUD.

# NOTE: This assumes that the required [$NC_ROOT/Powershell/*.ps1] files
#       in the current clone of the repo on the runner are up-to-date
#       enough to be able to obtain secrets and use GitHub Action functions.
#       If this is not the case, you'll have to manually pull the repo 
#       first on the runner.

$ncRoot = $env:NC_ROOT

if (![System.IO.Directory]::Exists($ncRoot))
{
  throw "Runner Config: neonCLOUD repo is not present."
}

$ncPowershell = [System.IO.Path]::Combine($ncRoot, "Powershell")

Push-Location $ncPowershell
. ./includes.ps1
Pop-Location
      
# Fetch the inputs.

$channel      = Get-ActionInput "channel"       $true
$operation    = Get-ActionInput "operation"     $true
$startTime    = Get-ActionInput "start-time"    $true
$finishTime   = Get-ActionInput "finish-time"   $true
$buildOutcome = Get-ActionInput "build-outcome" $true
$workflowRef  = Get-ActionInput "workflow-ref"  $true

# Parse the start/finish times and compute the elapsed time.

$startTime   = [System.DateTime]::Parse($startTime)
$finishTime  = [System.DateTime]::Parse($finishTime)
$elapsedTime = $(New-TimeSpan $startTime $finishTime)

# Determine the workflow run URI.

$workflowRunUri = "$env:GITHUB_SERVER_URL/$env:GITHUB_REPOSITORY/actions/runs/$env:GITHUB_RUN_ID"

# Convert [$workflowRef] into the URI to referencing the correct branch.  We're
# going to use the GITHUB_REF environment variable.  This includes the branch like:
#
#       refs/heads/master

if (!$workflowRef.Contains("/blob/master/"))
{
    throw "[workflow-ref=$workflowRef] is missing '/blob/master/'."
}

$githubRef    = $env:GITHUB_REF
$lastSlashPos = $githubRef.LastIndexOf("/")
$branch       = $githubRef.Substring($lastSlashPos + 1)
$workflowUri  = $workflowRef.Replace("/blob/master/", "/blob/$branch/")

# Set the accents based on the build outcome.

$buildOutcomeColor    = "default"
$buildOutcomeColorUri = "https://github.com/nforgeio-actions/images/blob/master/teams/warning.png"

Switch ($buildOutcome)
{
    "success"
    {
        $buildOutcomeColor    = "good"
        $buildOutcomeColorUri = "https://github.com/nforgeio-actions/images/blob/master/teams/ok.png"
    }

    "cancelled"
    {
        $buildOutcomeColor    = "warning"
        $buildOutcomeColorUri = "https://github.com/nforgeio-actions/images/blob/master/teams/warning.png"
    }

    "skipped"
    {
        $buildOutcomeColor    = "warning"
        $buildOutcomeColorUri = "https://github.com/nforgeio-actions/images/blob/master/teams/warning.png"
    }

    "failure"
    {
        $buildOutcomeColor    = "attention"
        $buildOutcomeColorUri = "https://github.com/nforgeio-actions/images/blob/master/teams/error.png"
    }
}

# We're going to use search/replace to modify a template card.  Here's the
# card documentation:
#
#   https://adaptivecards.io/explorer/

$card = 
@'
{
  "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
  "type": "AdaptiveCard",
  "version": "1.3",
  "body": [
    {
      "type": "Container",
      "backgroundImage": "@buildOutcomeColorUri",
      "items": [
        {
          "type": "TextBlock",
          "text": "@operation",
          "weight": "bolder",
          "size": "medium"
        },
        {
          "type": "ColumnSet",
          "columns": [
            {
              "type": "Column",
              "width": "auto",
              "items": [
                {
                  "type": "Image",
                  "url": "https://github.com/nforgeio-actions/images/blob/master/teams/devbot.png",
                  "size": "small",
                  "style": "person"
                }
              ]
            },
            {
              "type": "Column",
              "width": "stretch",
              "items": [
                {
                  "type": "TextBlock",
                  "spacing": "none",
                  "text": "devbot (neonFORGE)",
                  "wrap": true
                },
                {
                  "type": "TextBlock",
                  "spacing": "none",
                  "text": "@finish-time",
                  "isSubtle": true,
                  "wrap": true
                }
              ]
            }
          ]
        }
      ]
    },
    {
      "type": "Container",
      "items": [
        {
          "type": "FactSet",
          "facts": [
            {
              "title": "Outcome:",
              "value": "@build-outcome",
              "color": "@build-outcome-color"
            },
            {
              "title": "Runner:",
              "value": "@runner"
            },
            {
              "title": "Elapsed:",
              "value": "@elapsed-time"
            }
          ]
        },
        {
          "type": "ColumnSet",
          "columns": [
            {
              "type": "Column",
              "width": "stretch",
              "items": [
                {
                  "type": "ActionSet",
                  "actions": [
                    {
                      "type": "Action.OpenUrl",
                      "title": "Show Workflow Run",
                      "url": "@workflowRunUri",
                      "style": "positive"
                    }
                  ]
                }
              ]
            },
            {
              "type": "Column",
              "width": "stretch",
              "items": [
                {
                  "type": "ActionSet",
                  "actions": [
                    {
                      "type": "Action.OpenUrl",
                      "title": "Show Workflow",
                      "url": "@workflowUri",
                      "style": "positive"
                    }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}
'@

$card = $card.Replace("@operation", $operation)
$card = $card.Replace("@runner", $env:COMPUTERNAME)
$card = $card.Replace("@build-outcome", $buildOutcome.ToUpper())
$card = $card.Replace("@build-outcome-color", $buildOutcomeColor)
$card = $card.Replace("@workflowRunUri", $workflowRunUri)
$card = $card.Replace("@workflowUri", $workflowUri)
$card = $card.Replace("@start-time", $startTime.ToString("u"))
$card = $card.Replace("@finish-time", $finishTime.ToString("u"))
$card = $card.Replace("@elapsed-time", $elapsedTime.ToString("c"))

# Post the card to Microsoft Teams.

Invoke-WebRequest -Method "POST" -Uri $channel -ContentType "application/json" -Body $card 
