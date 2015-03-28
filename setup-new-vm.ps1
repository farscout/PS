<# .SYNOPSIS Setup a new environment with some common tools and installs #>

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
choco install launchy -y
choco install msbuild.communitytasks -y
choco install googledrive -y
choco install rdcman -y
choco install googlechrome -y

<# now create a localadmin user #>
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

