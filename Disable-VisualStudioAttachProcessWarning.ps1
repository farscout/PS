<# 
.DESCRIPTION
When you start up visual studio and are running an application
which attaches to a service also in your solution, you usually get
a warning about attaching to the service process.
This script will disable that warning
#>

$vsversion = "14.0" # VS 2013 (optionally "12.0" VS2013, 11, 10, 9, etc.)

#remember to close any open vstudios
#kill -name devenv # end any existing VS instances (required for persisting config change)
Get-ItemProperty -Path "HKCU:\Software\Microsoft\VisualStudio\$vsversion\Debugger" -Name DisableAttachSecurityWarning -ErrorAction SilentlyContinue # query value (ignore if not exists)
Set-ItemProperty -Path "HKCU:\Software\Microsoft\VisualStudio\$vsversion\Debugger" -Name DisableAttachSecurityWarning -Value 1 # assign value

