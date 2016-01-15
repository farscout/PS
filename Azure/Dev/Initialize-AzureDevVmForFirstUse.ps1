<# 
.DESCRIPTION
Setup a new environment in an Azure vm with some common tools and installs using chocolatey
.PARAMETER userName
the username for a local admin account this script will create
.PARAMETER password
the password for the local admin account this script will create
#>
[CmdletBinding()]
param($userName, $password)

#this will install chocolatey
iex ((new-object net.webclient).DownloadString('https://chocolatey.org/install.ps1'))

#this will install some chocolatey packages

choco install powershell -y
choco install pscx -y
choco install 7zip -y
choco install 7zip.commandline -y
choco install sublimetext3 -y
choco install sublimetext3.packagecontrol -y #package control manager for sublimetext3
choco install greenshot -y
choco install kdiff3 -y
choco install msbuild.communitytasks -y

# now create a localadmin user
$computerName = $env:ComputerName
$group = "Administrators"

$cn = [ADSI]"WinNT://$computerName"

$user = $cn.Create("User", $userName)

$user.SetPassword($password)

$user.setinfo()

$user.description = "Local Admin user for normal dev work"

$user.SetInfo()

#now add to local admin group
$objOU = [ADSI]"WinNT://$computerName/$group,group"

$objOU.add("WinNT://$computerName/$userName")

#now copy common files to local
$localCommon = "C:\commons"
if (-not(Test-Path -Path $localCommon)) {
	New-Item -ItemType Directory -Path $localCommon -force
}
#todo - copy from a common location

