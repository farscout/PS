
$secretConfigFile = "C:\G\a\configs\default-powershell-config.json"

$defaultSecretConfigs = Get-Content -Path $secretConfigFile | ConvertFrom-Json



$myLocation = Get-Location -PSProvider FileSystem
#Import-Module "SQLPS" -WarningAction SilentlyContinue #import the sql module
Set-Location $myLocation #reset the location as when you load SQL-PS it sets the current location to the SQL provider

function Show-SecretConfig {
    $defaultSecretConfigs
}
function Tester {
    [CmdletBinding()]
    param($f = $defaultSecretConfigs.DbAccessUserName,
        $g = $defaultSecretConfigs.DbAccessUserPassword
    )

    Write-Output ("f is $f and g is $g")
}

