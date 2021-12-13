#!/bin/sh

# WARNING! Parts of this script are destructive- make sure you check the bits that delete stuff...
# Heavily stolen from 
# https://scriptingosx.com/2021/07/notarize-a-command-line-tool-with-notarytool/
# With thanks to Armin Briegel

# loads of unneccesary checks included, strip these out when ready...

# Exit script if anything fails. This can be commented out when working properly
set -e

# Specify your variables here- sample text included for reference
# this script assumes you are installing a command line tool in /usr/local edit line 140 if this is not true
version="1.0"
author="NotApple"
project="MyProject"
identifier="com.notapple.myproject"
productname="myproject"
rawbinary="myproject-darwin"
icon="myproject.png"

# Apple Developer account email address
dev_account="email@company.com"
# Name of keychain item containing app password for signing
dev_keychain_label="Developer-altool"
# Name of file containing security entitlements- 
# this file must be in the build folder, signing the binary also attaches these entitlements
entitlements="myproject.entitlements"
# Signature to use for building installer package
signature="Developer ID Installer: Company Pty Ltd (xxxxx)"
Developer_ID_Application="Developer ID Application: Company Pty Ltd (xxxxx)"

# Main project directory- the location of this script!
projectdir="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
echo $projectdir
#Location where the raw download, icon file, info.plist and entitlements file must exist                        
builddir="$projectdir/build" 
# build root- this is location of signed binary to build into pkg
pkgroot="$projectdir/$productname"
# Location where our .pkg will be saved for notarisation
pkgpath="$builddir/$productname-$version.pkg"

# functions
requeststatus() { # $1: requestUUID
    requestUUID=${1?:"need a request UUID"}
    req_status=$(xcrun altool --notarization-info "$requestUUID" \
                              --username "$dev_account" \
                              --password "@keychain:$dev_keychain_label" 2>&1 \
                 | awk -F ': ' '/Status:/ { print $2; }' )
    echo "$req_status"
}

notarizefile() { # $1: path to file to notarize, $2: identifier
    filepath=${1:?"need a filepath"}
    identifier=${2:?"need an identifier"}
    
    # upload file
    echo "## uploading $filepath for notarization"
    requestUUID=$(xcrun altool --notarize-app \
                               --primary-bundle-id "$identifier" \
                               --username "$dev_account" \
                               --password "@keychain:$dev_keychain_label" \
                               --asc-provider "$dev_team" \
                               --file "$filepath" 2>&1 \
                  | awk '/RequestUUID/ { print $NF; }')
                               
    echo "Notarization RequestUUID: $requestUUID"
    
    if [[ $requestUUID == "" ]]; then 
        echo "could not upload for notarization"
        exit 1
    fi
        
    # wait for status to be not "in progress" any more
    request_status="in progress"
    while [[ "$request_status" == "in progress" ]]; do
        echo -n "waiting... "
        sleep 10
        request_status=$(requeststatus "$requestUUID")
        echo "$request_status"
    done
    
    # print status information
    xcrun altool --notarization-info "$requestUUID" \
                 --username "$dev_account" \
                 --password "@keychain:$dev_keychain_label"
    echo 
    
    if [[ $request_status != "success" ]]; then
        echo "## could not notarize $filepath"
        exit 1
    fi
    
}

# Get latest binary
# We need the latest binary of a particular build. For releases with a single download that isn;t so difficult, but it's a pain here
# We can do this if we follow redirects-
# https://github.com/$author/$project/releases/latest/download/netclient-darwin
# 

# let's make sure we are in the correct directory
cd $builddir
echo we are in $builddir

# Cleaning out from previous runs
echo Cleaning out from previous runs- WARNING- destructive!

rm -rf $builddir"/$productname"
rm -rf $builddir"/$productname.pkg"
rm -rf "$projectdir/usr/local/$productname"


echo  Getting Latest $binary Package via Github
echo Downloading to $PWD

curl -L  https://github.com/$author/$project/releases/latest/download/$rawbinary --output $rawbinary
if  [ $? -eq 0 ]
then
     echo Downloading $rawbinary Package Succeeded
else
     echo Downloading $rawbinary Package Failed
fi

# Rename download
mv $rawbinary $productname

# Codesign Binary
# make sure entitlements file is in the raw binary folder
codesign --deep --force --options=runtime --sign "$Developer_ID_Application" --timestamp ./$productname
if  [ $? -eq 0 ]
then
     echo signing $binary Package Succeeded
else
     echo signing $binary Package Failed
fi



# copy the signed binary into the folder structure to mirror install location

cp $builddir"/$productname" "$projectdir/$productname/usr/local/$productname"

pkgbuild --root "$projectdir/$productname" \
         --identifier "$identifier" \
         --version "$version" \
         --install-location "/" \
         --sign "$signature" \
         $builddir"/$productname-$version.pkg"
# Build into a .pkg and Sign the bundle 
if  [ $? -eq 0 ]
then
     echo pkgbuild Succeeded
else
     echo pkgbuild Failed
fi

# upload for notarization
notarizefile "$pkgpath" "$identifier"

# staple result
echo "## Stapling $pkgpath"
xcrun stapler staple "$pkgpath"

echo '## Done!'
echo lets check our work 
spctl --assess -vv --type install $pkgpath

# show the pkg in Finder
open -R "$pkgpath"

exit 0

fi
