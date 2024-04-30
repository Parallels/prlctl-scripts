param (
  [string]$DESTINATION = "c:\action-runner",
  [string]$ORGANIZATION_NAME,
  [string]$TOKEN,
  [string]$RUN_AS = $env:USERNAME,
  [string]$NAME = $env:COMPUTERNAME,
  [string]$LABELS,
  [string]$GROUP
)

if ([string]::IsNullOrEmpty($ORGANIZATION_NAME)) {
  Write-Host "Organization name is required"
  exit 1
}

if ([string]::IsNullOrEmpty($TOKEN)) {
  Write-Host "PAT Token is required"
  exit 1
}

function Configure {
  # Getting the registration token
  Write-Host "Configuring the actions runner for $ORGANIZATION_NAME"
  $URL_PATH = "orgs/$ORGANIZATION_NAME"
  if ($ORGANIZATION_NAME -like "*/*") {
    Write-Host "This seems to be a request for a repository runner"
    $URL_PATH = "repos/$ORGANIZATION_NAME"
  }

  # Rest of the code...
  $AUTH_TOKEN = (Invoke-RestMethod -Method POST -Uri "https://api.github.com/$URL_PATH/actions/runners/registration-token" -Headers @{
    "Accept" = "application/vnd.github+json"
    "Authorization" = "token $TOKEN"
    "X-GitHub-Api-Version" = "2022-11-28"
  }).token
  Write-Host "Auth Token is $AUTH_TOKEN"

  # Create the runner and start the configuration experience
  Write-Host "Configuring the runner as $RUN_AS"
  $OPTIONS = "--url https://github.com/$ORGANIZATION_NAME --token $AUTH_TOKEN"
  if (![string]::IsNullOrEmpty($LABELS)) {
    $OPTIONS += " --labels $LABELS"
  }
  if (![string]::IsNullOrEmpty($NAME)) {
    $OPTIONS += " --name $NAME"
  }
  if (![string]::IsNullOrEmpty($GROUP)) {
    Write-Host "test"
    $OPTIONS += " --group $GROUP"
  }
  Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$DESTINATION\config.cmd $OPTIONS --unattended --runasservice`"" -Verb RunAs -Wait
}

Configure
Write-Host "Done"
