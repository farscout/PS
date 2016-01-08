<#
.DESCRIPTION
Setup using my profile on a new computer
#>
New-Item -ItemType File -Path $profile -Force
$profileContent = ". " + (Join-Path -Path $PSScriptRoot -ChildPath ".profile.ps1")
Set-Content -Path $profile -Value $profileContent
Write-Output "Profile now using content: "
Write-Output $profileContent
