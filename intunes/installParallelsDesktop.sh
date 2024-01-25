#!/bin/bash
#set -x

############################################################################################
##
## Script to download and install Parallels Desktop using Parallels Deployment Package
## PAY ATTENTION TO THE INSTRUCTIONS SECTION BELOW
##
############################################################################################

## © 2023 Parallels International GmbH. All rights reserved.
## The scripts are provided AS IS without warranty of any kind.
## Parallels disclaims all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a
## particular purpose. The entire risk arising out of the use or performance of the scripts and documentation remains with you. In no event shall
## Parallels, its authors, or anyone else involved in the creation, production, or delivery of the scripts be liable for any damages whatsoever
## (including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary
## loss) arising out of the use of or inability to use the sample scripts or documentation, even if Parallels has been advised of the possibility
## of such damages.

## This script uses parts of the Microsoft code written available at 
## https://github.com/microsoft/shell-intune-samples/blob/master/macOS/Apps/
## Copyright (c) 2020 Microsoft Corp. All rights reserved.
## Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
## THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## Parallels team would like to thank Microsoft for sharing their code. This was instrumental in building this script and  
## enabling administrators to deploy Parallels Desktop with help of Microsoft Endpoint Management (Intune).

############################################################################################
## INSTRUCTIONS
## 1. Download Parallels Desktop Autodeploy Package from https://www.parallels.com/products/business/download/
## 2. Prepare the Autodeploy Package package by following instructions in the Administrator's Guide at https://www.parallels.com/products/business/resources/
## 3. Rename and Zip the Parallels Desktop Autodeploy Package.
## 4. Upload the package to Azure blob or other network storage and provide an URL in the weburl variable below.
## 5. Use the script to install Parallels Desktop following Microsoft's instructions at https://learn.microsoft.com/en-us/mem/intune/apps/macos-shell-scripts 
##

# User Defined variables
weburl="https://fe.parallels.com/bbc828c8b36cec2d7a8d4fc1bc0ef2a3/Parallels.pkg.zip"                # !!! Upload package to Azure blob or local storage and provide an URL
appname="Parallels Desktop"                                                                         # The name of our App deployment script (also used for Octory monitor)

# Generated variables
tempdir=$(mktemp -d)
log="/Library/Logs/parallels-installscript.log"                                                     # The location of the script log file

# function to delay script if the specified process is running
waitForProcess () {

    #################################################################################################################
    #################################################################################################################
    ##
    ##  Function to pause while a specified process is running
    ##
    ##  Functions used
    ##
    ##      None
    ##
    ##  Variables used
    ##
    ##      $1 = name of process to check for
    ##      $2 = length of delay (if missing, function to generate random delay between 10 and 60s)
    ##      $3 = true/false if = "true" terminate process, if "false" wait for it to close
    ##
    ###############################################################
    ###############################################################

    processName=$1
    fixedDelay=$2
    terminate=$3

    echo "$(date) | Waiting for other [$processName] processes to end"
    while ps aux | grep "$processName" | grep -v grep &>/dev/null; do

        if [[ $terminate == "true" ]]; then
            echo "$(date) | + [$appname] running, terminating [$processpath]..."
            pkill -f "$processName"
            return
        fi

        # If we've been passed a delay we should use it, otherwise we'll create a random delay each run
        if [[ ! $fixedDelay ]]; then
            delay=$(( $RANDOM % 50 + 10 ))
        else
            delay=$fixedDelay
        fi

        echo "$(date) |  + Another instance of $processName is running, waiting [$delay] seconds"
        sleep $delay
    done
    
    echo "$(date) | No instances of [$processName] found, safe to proceed"

}

function downloadApp () {

    #################################################################################################################
    #################################################################################################################
    ##
    ##  This function takes the following global variables and downloads the URL provided to a temporary location
    ##
    ##  Functions
    ##
    ##      waitForCurl (Pauses download until all other instances of Curl have finished)
    ##      downloadSize (Generates human readable size of the download for the logs)
    ##
    ##  Variables
    ##
    ##      $appname = Description of the App we are installing
    ##      $weburl = URL of download location
    ##      $tempfile = location of temporary DMG file downloaded
    ##
    ###############################################################
    ###############################################################

    echo "$(date) | Starting downloading of [$appname]"

    # wait for other downloads to complete
    waitForProcess "curl -f"

    #download the file
    echo "$(date) | Downloading $appname"

    cd "$tempdir"
    curl -f -s --connect-timeout 30 --retry 5 --retry-delay 60 -L -J -O "$weburl"
    if [ $? == 0 ]; then

            # We have downloaded a file, we need to know what the file is called
            tempSearchPath="$tempdir/*"
            for f in $tempSearchPath; do
                tempfile=$f
            done
         
    else
    
        echo "$(date) | Failure to download [$weburl] to [$tempfile]"
         updateOctory failed
         exit 1
    fi

}

## 
function unpackZIP () {

    echo "$(date) | Installing $appname"
    updateOctory installing

    # Change into temp dir
    cd "$tempdir"
    if [ "$?" = "0" ]; then
      echo "$(date) | Changed current directory to $tempdir"
    else
      echo "$(date) | failed to change to $tempfile"
      if [ -d "$tempdir" ]; then rm -rf $tempdir; fi
      updateOctory failed
      exit 1
    fi

    # Unzip files in temp dir
    unzip -qq -o "$tempfile"
    rm -rf "$tempfile"
    if [ "$?" = "0" ]; then
      echo "$(date) | $tempfile unzipped"
    else
      echo "$(date) | failed to unzip $tempfile"
      if [ -d "$tempdir" ]; then rm -rf $tempdir; fi
      updateOctory failed
      exit 1
    fi

    ## Get the path to the PKG file
    tempSearchPath="$tempdir/*"
    for f in $tempSearchPath; do
        if [[ $f == *.pkg ]]; then tempfile=$f; fi
    done
    echo "$(date) | the package name is $tempfile"

    ## Remote quarantine attribute
    xattr -r -d com.apple.quarantine $tempfile

}

## Install PKG Function
function installPKG () {

    # Update Octory monitor
    updateOctory installing

    installer -pkg "$tempfile" -target /Applications

    # Checking if the app was installed successfully
    if [ "$?" = "0" ]; then

        echo "$(date) | $appname Installed"
        echo "$(date) | Cleaning Up"
        rm -rf "$tempdir"

        echo "$(date) | Application [$appname] succesfully installed"
        updateOctory installed
        exit 0

    else

        echo "$(date) | Failed to install $appname. Check /private/var/log/install.log for details."
        rm -rf "$tempdir"
        updateOctory failed
        exit 1
    fi

}


function updateOctory () {

    #################################################################################################################
    #################################################################################################################
    ##
    ##  This function is designed to update Octory status (if required)
    ##
    ##
    ##  Parameters (updateOctory parameter)
    ##
    ##      notInstalled
    ##      installing
    ##      installed
    ##
    ###############################################################
    ###############################################################

    # Is Octory present
    if [[ -a "/Library/Application Support/Octory" ]]; then

        # Octory is installed, but is it running?
        if [[ $(ps aux | grep -i "Octory" | grep -v grep) ]]; then
            echo "$(date) | Updating Octory monitor for [$appname] to [$1]"
            /usr/local/bin/octo-notifier monitor "$appname" --state $1 >/dev/null
        fi
    fi

}

function startLog() {

    ###################################################
    ###################################################
    ##
    ##  start logging - Output to log file and STDOUT
    ##
    ####################
    ####################

    exec &> >(tee -a "$log")
    
}

# function to delay until the user has finished setup assistant.
waitForDesktop () {
  until ps aux | grep /System/Library/CoreServices/Dock.app/Contents/MacOS/Dock | grep -v grep &>/dev/null; do
    delay=$(( $RANDOM % 50 + 10 ))
    echo "$(date) |  + Dock not running, waiting [$delay] seconds"
    sleep $delay
  done
  echo "$(date) | Dock is here, lets carry on"
}

###################################################################################
###################################################################################
##
## Begin Script Body
##
#####################################
#####################################

# Initiate logging
startLog

echo ""
echo "##############################################################"
echo "# $(date) | Logging install of [$appname] to [$log]"
echo "############################################################"
echo ""

# Wait for Desktop
waitForDesktop

# Download app
downloadApp

# Unpack PKG bundle from ZIP
unpackZIP

# Install PKG file
installPKG
