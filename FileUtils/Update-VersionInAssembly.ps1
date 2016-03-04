<#
.DESCRIPTION
Update the versions in the AssemblyInfo.cs file preperatory to build
.PARAMETER File
the location of AssemblyInfo.cs to update, if not supplied, assumption is current folder or in Properties subfolder
#>

[CmdletBinding()]
param($File,
    $AssemblyVersion = "1.0.0.1", 
    $AssemblyDescription)

$assemblyVersionfileName = "AssemblyInfo.cs"

if (-not ($AssemblyDescription)) {
    $dtg = (get-date).ToString("yyyymmdd_HHmm")
    $AssemblyDescription = "$dtg release"
}
if (-not $File) {
    $fileNameAndPath = Join-Path -Path $PSScriptRoot -ChildPath $assemblyVersionfileName
    if (Test-Path -Path $fileNameAndPath) {
        $File = $fileNameAndPath
    }
    else {
        $propertiesPath = Join-Path -Path $PSScriptRoot -ChildPath "Properties"
        $fileNameAndPath = Join-Path -Path $propertiesPath -ChildPath $assemblyVersionfileName
        if (-not (Test-Path -Path $fileNameAndPath)) {
            Write-Error "Could not locate the $assemblyVersionfileName in the root or even the properties subfolder"
            return
        }
    }
    $File = $fileNameAndPath
}

if (-not (Test-Path -Path $File)) {
    Write-Error "Could not find $assemblyVersionfileName at the path you specified $File"
    return
}

$content = Get-Content -Path $File

$patternAssemblyVersion = "AssemblyVersion\(.+\)"
$patternAssemblyFileVersion = "AssemblyFileVersion\(.+\)"
$patternAssemblyDescription = "AssemblyDescription\(.+\)"

$content = $content -replace $patternAssemblyVersion, "AssemblyVersion(""$AssemblyVersion"")"
$content = $content -replace $patternAssemblyFileVersion, "AssemblyFileVersion(""$AssemblyVersion"")"
$content = $content -replace $patternAssemblyDescription, "AssemblyDescription(""$AssemblyDescription"")"

$content

