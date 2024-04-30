param (
  [string]$DESTINATION = "c:\action-runner",
  [string]$ORGANIZATION_NAME,
  [string]$TOKEN,
  [string]$RUN_AS = $env:USERNAME
)

if (-not $ORGANIZATION_NAME) {
  Write-Host "Organization name is required"
  exit 1
}

if (-not $TOKEN) {
  Write-Host "PAT Token is required"
  exit 1
}

function Remove {
  # Getting the registration token
  Write-Host "Removing the actions runner from $ORGANIZATION_NAME"
  $URL_PATH = "orgs/$ORGANIZATION_NAME"
  if ($ORGANIZATION_NAME -like "*/*") {
    Write-Host "This seems to be a request for a repository runner"
    $URL_PATH = "repos/$ORGANIZATION_NAME"
  }

  # Rest of the code...
  $AUTH_TOKEN = (Invoke-RestMethod -Uri "https://api.github.com/$URL_PATH/actions/runners/registration-token" -Method POST -Headers @{
    "Accept" = "application/vnd.github+json"
    "Authorization" = "token $TOKEN"
    "X-GitHub-Api-Version" = "2022-11-28"
  }).token
  Write-Host "Auth Token is $AUTH_TOKEN"

  Start-Process -FilePath "$DESTINATION\config.cmd" -ArgumentList "remove", "--token", $AUTH_TOKEN -NoNewWindow -Wait
}

function Cleanup {
  Write-Host "Cleaning up the installation"
  Remove-Item -Path $DESTINATION -Recurse -Force

  Write-Host "Removing the service"
}

Remove
Cleanup
Write-Host "Done"
