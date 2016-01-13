<# .DESCRIPTION
Set some common stuff in the profile
#>

function prompt { "#" }

Set-Location -Path C:\

#some env variables for building in vstudio
$env:VisualStudioVersion="14.0"

function gos {
    <# .DESCRIPTION 
    Go to the scripts folder 
    #>
    Set-Location "C:\G\a\PSScripts"
    pwd
}

function goc {
    <# .DESCRIPTION 
    Go to the c root drive 
    #>
    Set-Location "C:\"
    pwd
}

function godb {
    Set-Location "c:\db\files"
    pwd
}

"profile script complete"
"Adapt or die"
