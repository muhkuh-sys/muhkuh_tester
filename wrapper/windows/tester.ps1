# Run the lua5.1.exe in the path of this scrip file. Here is a way how to get the path of this script:
# https://stackoverflow.com/questions/5466329/whats-the-best-way-to-determine-the-location-of-the-current-powershell-script
# This works for all versions of Powershell.
$SELFDIR = [System.IO.Path]::GetDirectoryName($myInvocation.MyCommand.Definition)
$SELFDIR\lua5.1 $SELFDIR\system.lua --color %*
