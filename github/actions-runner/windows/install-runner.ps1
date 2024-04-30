param (
  [string]$DESTINATION = "c:\",
  [string]$RUN_AS = $env:USERNAME
)

if (-not $DESTINATION) {
  Write-Host "Setting the destination to $HOME"
  $DESTINATION = $env:USERPROFILE
}

if (-not $RUN_AS) {
  $RUN_AS = $env:USERNAME
}

if (-not $NAME) {
  $NAME = $env:COMPUTERNAME
}

function Install {
  Write-Host "Getting the latest version of the GitHub Actions runner"
  # Create a folder
  Write-Host "Creating a folder $DESTINATION/action-runner"
  New-Item -ItemType Directory -Path "$DESTINATION/action-runner" | Out-Null
  Set-Location "$DESTINATION/action-runner"
  # Get the latest version of the GitHub Actions runner
  $LATEST_VERSION = (Invoke-RestMethod -Uri "https://api.github.com/repos/actions/runner/releases/latest").tag_name
  $LASTEST_VERSION_SMALL = $LATEST_VERSION -replace 'v'

  # Get the architecture and define some common names
  $ARCHITECTURE = (Get-WmiObject -Class Win32_ComputerSystem).SystemType
  if ($ARCHITECTURE -eq "x64") {
    $ARCHITECTURE = "x64"
  }
  if ($ARCHITECTURE -eq "ARM64") {
    $ARCHITECTURE = "arm64"
  }
  if ($ARCHITECTURE -eq "ARM64-based PC") {
    $ARCHITECTURE = "arm64"
  }

  $LABELS += ",$ARCHITECTURE"

  Write-Host "Latest version is $LATEST_VERSION for architecture $ARCHITECTURE"

  Write-Host "Downloading the latest version of the GitHub Actions runner"
  # Download the latest runner package
  Invoke-WebRequest -Uri "https://github.com/actions/runner/releases/download/$LATEST_VERSION/actions-runner-win-$ARCHITECTURE-$LASTEST_VERSION_SMALL.zip" -OutFile "actions-runner-win-$ARCHITECTURE-$LASTEST_VERSION_SMALL.zip"

  Write-Host "Extracting the latest version of the GitHub Actions runner"
  # Extract the installer
  Expand-Archive -Path "actions-runner-win-$ARCHITECTURE-$LASTEST_VERSION_SMALL.zip" -DestinationPath . -Force

  Remove-Item -Path "actions-runner-win-$ARCHITECTURE-$LASTEST_VERSION_SMALL.zip"
}

Write-Host "Installing the GitHub Actions runner into $DESTINATION as $RUN_AS"

Install
Write-Host "Done"
