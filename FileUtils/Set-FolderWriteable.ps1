<#
.DESCRIPTION
Example command for forcing all files in a folder and below to
to be writeable. Typically used when getting source files from
tfs and modifying during a build without read-only causing build errors
.PARAMETER folder
path to recurse into and below making all files writeable
#>
[CmdletBinding()]
param($folder)

gci -Path $folder -Recurse -attributes readonly | % { $_.IsReadonly = $false }
