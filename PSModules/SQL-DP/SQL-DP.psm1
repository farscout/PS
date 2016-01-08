<#
.DESCRIPTION
Common SQL actions lib to help me in my work
DP.

.NOTES
There will be a config file located somewhere else and referenced in this powershell module
to provide secret usernames and passwords as defaults when running this code
will be of the form:
    "DbAccessUserName":"",
    "DbAccessUserPassword":"",
    "SqlServerUserName":"",
    "SqlServerUserPassword":"",
    "SqlServerDefaultInstance":"",
    "SqlDefaultDataLocation":"",
    "SqlDefaultDatabaseName":"",
    "SqlDefaultDatabaseLogName":"",
    "DefaultLogFolderName":""
#>

$secretConfigFile = "C:\G\a\configs\default-sql-dp-ps-config"
if (-not (Test-Path -Path $secretConfigFile)) {
    Write-Error "Could not locate the default secret config file at $secretConfigFile. Stopping"
    exit 1
}

$defaultSecretConfigs = Get-Content -Path $secretConfigFile | ConvertFrom-Json



$myLocation = Get-Location -PSProvider FileSystem
Import-Module "SQLPS" -WarningAction SilentlyContinue #import the sql module
Set-Location $myLocation #reset the location as when you load SQL-PS it sets the current location to the SQL provider

function Show-DpSecretConfig {
    $defaultSecretConfigs
}

return

function Set-DpUserEnsureLogin {
    <# 
    .DESCRIPTION 
    Ensure the database login exists on the designated sql server.
    This is preperatory to restoring a database which requires the user to already exist 
    #>
    [CmdletBinding()]
    param (
        [string] $userToEnsure = $defaultSecretConfigs.DbAccessUserName, 
        [string] $passwordToEnsure = $defaultSecretConfigs.DbAccessUserPassword, 
        [string] $sqlServer = $defaultSecretConfigs.SqlServerDefaultInstance, 
        [string] $userName = $defaultSecretConfigs.SqlServerUserName, 
        [string] $password = $defaultSecretConfigs.SqlServerUserPassword
    )
    $queryTimeout = [int] 1200 

    #check if user already exists
    $sql = @"
    use [master]
    go
    select * from sys.sql_logins
    where name='$userToEnsure'
"@
    $result = Invoke-Sqlcmd `
        -ServerInstance $sqlServer `
        -Username $userName `
        -Password $password `
        -Query $sql `
        -QueryTimeout $queryTimeout

    if ($result.Count -eq 0) {
        Write-Verbose ($userToEnsure + " does not already exist...creating")

        $sql = @"
USE [master]
GO
CREATE LOGIN [$userToEnsure] WITH PASSWORD=N'$passwordToEnsure', DEFAULT_DATABASE=[master], CHECK_EXPIRATION=OFF, CHECK_POLICY=OFF
GO
EXEC master..sp_addsrvrolemember @loginame = N'$userToEnsure', @rolename = N'sysadmin'

GO
"@

        Write-Verbose "Executing below sql to add user"
        Write-Verbose $sql

        $result = Invoke-Sqlcmd `
            -ServerInstance $sqlServer `
            -Username $userName `
            -Password $password `
            -Query $sql `
            -QueryTimeout $queryTimeout

        Write-Verbose ($userToEnsure + " created")
    }
    else {
        Write-Verbose ($userToEnsure + " already exists")
    }
}



function Use-DpSqlScripts {

    <#
    .DESCRIPTION
    Run all the sql scripts in the passed in folder, sorted by their filenames

    .EXAMPLE
    Use-SqlScripts -folderName 'c:\updatescripts'
    
    .SYNOPSIS
    Defaults will be read from the defaults file.
    If you want to scripts to exec against another db other than the default, then
    pass it in explicitly or have use [dbname] at the top of the scripts
    You can use the -Whatif true param to specify the script should not execute, but should only 
    show the list of scripts it will execute against.

    .PARAMETER folderName
    if not passed in, will search the current folder for scripts to run

    #>
    [CmdletBinding(SupportsShouldProcess=$True)]
    param([string] $folderName, 
        [string] $sqlServer = $defaultSecretConfigs.SqlServerDefaultInstance, 
        [string] $userName = $defaultSecretConfigs.SqlServerUserName, 
        [string] $password = $defaultSecretConfigs.SqlServerUserPassword,
        [string] $databaseName = $defaultSecretConfigs.SqlDefaultDatabaseName
    )

    if (-not ($folderName)) {
        $folderName = Get-Location -PSProvider FileSystem
    }
    $queryTimeout = [int] 1200 #make it a large number as some scripts can be nasty in their long-ness

    if (-not (Test-Path -Path $folderName)) {
        Write-Error "Could not find folder to work within"
        exit 1
    }
    
    $sqlScripts = Get-ChildItem -Path $folderName -File -Filter "*.sql" | sort -Property "Name"
    
    foreach ($s in $sqlScripts) {

        if ($pscmdlet.ShouldProcess("Invoke-Sqlcmd", "$s")) {
            $result = Invoke-Sqlcmd `
                -ServerInstance $sqlServer `
                -Database $databaseName `
                -Username $userName `
                -Password $password `
                -InputFile $s.FullName `
                -QueryTimeout $queryTimeout
            Write-Verbose $s.Name
        }
    }

}


