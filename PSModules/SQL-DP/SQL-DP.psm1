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

$secretConfigFile = "C:\G\a\configs\default-sql-dp-ps-config.json"
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


function Restore-DPDb {
    <#
    .DESCRIPTION
    Restore a database

    #>
    [CmdletBinding(SupportsShouldProcess=$True)]
    param([string] $dbName = $defaultSecretConfigs.SqlDefaultDatabaseName, 
        [string] $workingFolder, 
        [string] $dataLocation = $defaultSecretConfigs.SqlDefaultDataLocation, 
        [string] $databaseFileName, 
        [string] $logicalFileName, 
        [string] $logicalLogName, 
        [string] $sqlServer = $defaultSecretConfigs.SqlServerDefaultInstance, 
        [string] $userName = $defaultSecretConfigs.SqlServerUserName, 
        [string] $password = $defaultSecretConfigs.SqlServerUserPassword, 
        [string] $scriptToRunAfter,
        [string] $sqlCommandStringToRunAfter
    )

    if (-not ($workingFolder)) {
        $workingFolder = Get-Location -PSProvider FileSystem
    }

    $queryTimeout = [int] 1200 #make it a large number as some restores can take time

    $sqlTemplate = @"
    USE [master]
    go
    if (db_id('PARAM_DB_NAME') is not null)
    begin
        ALTER DATABASE [PARAM_DB_NAME] SET SINGLE_USER WITH ROLLBACK IMMEDIATE
    end
    go
    RESTORE DATABASE [PARAM_DB_NAME] FROM  DISK = N'PARAM_DB_PATH_AND_NAME.bak'
    WITH  FILE = 1,
    MOVE N'PARAM_LOGICAL_DB_NAME' TO 
    N'PARAM_DATA_LOCATION\PARAM_DB_NAME.mdf',  
    MOVE N'PARAM_LOGICAL_LOG_NAME' TO 
    N'PARAM_DATA_LOCATION\PARAM_LOGICAL_DESTINATION_LOG_NAME.ldf',
    NOUNLOAD, REPLACE, STATS=5
    go
    ALTER DATABASE [PARAM_DB_NAME] SET MULTI_USER
    go
"@
   
    $logicalLogNameDestination = $dbName + "_log"
    
    if (-not $logicalLogName) {
        if ($logicalFileName) {
            $logicalLogName = $logicalFileName + "_log"
        }
        else {
            $logicalLogName = $dbName + "_log"
        }
    }

    if (-not($logicalFileName)) {
        $logicalFileName = $dbName
    }

    if ($databaseFileName) {
        if (-not ($databaseFileName -match "\\")) {
            #no full path - make it a full path
            $databaseFileName = Join-Path -Path $workingFolder -ChildPath $databaseFileName
        }
        $databaseFileName = $databaseFileName -replace "\.bak$", "" #remove any .bak file append, as we will put it in explicitly in the sql template
    }
    else {
        $databaseFileName = Join-Path -Path $workingFolder -ChildPath $dbName
    }
    
    $sqlTemplate = $sqlTemplate -replace "PARAM_DB_NAME", $dbName
    $sqlTemplate = $sqlTemplate -replace "PARAM_LOGICAL_DB_NAME", $logicalFileName
    $sqlTemplate = $sqlTemplate -replace "PARAM_LOGICAL_LOG_NAME", $logicalLogName
    $sqlTemplate = $sqlTemplate -replace "PARAM_LOGICAL_DESTINATION_LOG_NAME", $logicalLogNameDestination

    $sqlTemplate = $sqlTemplate -replace "PARAM_DB_PATH_AND_NAME", $databaseFileName
    $sqlTemplate = $sqlTemplate -replace "PARAM_DATA_LOCATION", $dataLocation

    Write-Verbose "running the below constructed command to restore your database"
    Write-Verbose $sqlTemplate 

    if ($Whatif) {
        Write-Output "Whatif: execute the statement to restore the database"
    }
    else {
        $result = Invoke-Sqlcmd `
            -ServerInstance $sqlServer `
            -Username $userName `
            -Password $password `
            -Query $sqlTemplate `
            -QueryTimeout $queryTimeout
    }

    Write-Verbose "Completed restoring $dbName"

    $updateDbOwnerSqlTemplate = @"
        USE [PARAM_DB_NAME]
        GO
        EXEC dbo.sp_changedbowner @loginame = N'PARAM_LOGIN_NAME', @map = false
        GO
"@
    $updateDbOwnersql = $updateDbOwnerSqlTemplate -replace "PARAM_DB_NAME", $dbName
    $updateDbOwnersql = $updateDbOwnersql -replace "PARAM_LOGIN_NAME", $userName
    
    Write-Verbose "updating the database owner to the userName $userName you passed in"
    Write-Verbose "executing the following sql to update the database owner"
    Write-Verbose $updateDbOwnersql

    if ($Whatif) {
        Write-Output "Whatif: execute the statement to update the database owner"
    }
    else {
        $result = Invoke-Sqlcmd `
            -ServerInstance $sqlServer `
            -Username $userName `
            -Password $password `
            -Query $updateDbOwnersql `
            -QueryTimeout $queryTimeout
        Write-Verbose "Database owner updated to $userName"
    }

    if ($scriptToRunAfter) {
        Write-Verbose "Running your post restore script $scriptToRunAfter"
        #did user have a directory on the filename or was it just the filename
        if (-not ($scriptToRunAfter -match "\\")) {
            $scriptToRunAfter = Join-Path $workingFolder -ChildPath $scriptToRunAfter
        }
        if (-not(Test-Path -Path $scriptToRunAfter)) {
            Write-Error "Could not locate your post restore script $scriptToRunAfter - check the filename you gave me"
        }
        else {
            if ($Whatif) {
                Write-Output "Whatif: execute the statement to run script after named $scriptToRunAfter"
            }
            else {
                $result = Invoke-Sqlcmd `
                    -ServerInstance $sqlServer `
                    -Username $userName `
                    -Password $password `
                    -InputFile $scriptToRunAfter `
                    -QueryTimeout $queryTimeout
            }
        }
    }

    if ($sqlCommandStringToRunAfter) {
        if ($Whatif) {
            Write-Output "Executing your sql command after restoring the database: "
            Write-Output $sqlCommandStringToRunAfter
        }
        else {
            $result = Invoke-Sqlcmd `
                -ServerInstance $sqlServer `
                -Username $userName `
                -Password $password `
                -Query $sqlCommandStringToRunAfter `
                -QueryTimeout $queryTimeout
            Write-Verbose "Executed your sql command after restoring the database: "
            Write-Verbose $sqlCommandStringToRunAfter
        }
    }

    Write-Output "Restore-DPDb Complete"

}

