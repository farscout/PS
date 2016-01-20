<#
.SYNOPSIS
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

function Show-DPSecretConfig {
    $defaultSecretConfigs
}



function Set-DpUserEnsureLogin {
    <# 
    .SYNOPSIS 
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



function Use-DPSqlScripts {

    <#
    .SYNOPSIS
    Run all the sql scripts in the passed in folder, sorted by their filenames.
    Defaults will be read from the defaults file.
    If you want to scripts to exec against another db other than the default, then
    pass it in explicitly or have use [dbname] at the top of the scripts
    You can use the -Whatif switch to specify the script should not execute, but should only 
    show the list of scripts it will execute against.

    .EXAMPLE
    Use-SqlScripts -folderName 'c:\updatescripts'

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
        return $False
    }
    
    $sqlScripts = Get-ChildItem -Path $folderName -File -Filter "*.sql" | sort -Property "Name"
    
    foreach ($s in $sqlScripts) {
        if ($pscmdlet.ShouldProcess("$s", "Invoke-Sqlcmd")) {
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
    .SYNOPSIS
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
        [string] $sqlCommandStringToRunAfter,
        [string] $runAllScriptsThisFolder
    )

    if (-not ($workingFolder)) {
        $workingFolder = Get-Location -PSProvider FileSystem
    }

    $queryTimeout = [int] 2000 #make it a large number as some restores can take time

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

    if ($PSCmdlet.ShouldProcess($sqlTemplate, "Invoke-Sqlcmd")) {
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

    if ($PSCmdLet.ShouldProcess($updateDbOwnersql, "Invoke-Sqlcmd")) {
        $result = Invoke-Sqlcmd `
            -ServerInstance $sqlServer `
            -Username $userName `
            -Password $password `
            -Query $updateDbOwnersql `
            -QueryTimeout $queryTimeout
        
    }
    Write-Verbose "Database owner updated to $userName"

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
            if ($PSCmdLet.ShouldProcess($scriptToRunAfter, "Invoke-Sqlcmd")) {
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
        if ($PSCmdLet.ShouldProcess($sqlCommandStringToRunAfter, "Invoke-Sqlcmd")) {
            $result = Invoke-Sqlcmd `
                -ServerInstance $sqlServer `
                -Username $userName `
                -Password $password `
                -Query $sqlCommandStringToRunAfter `
                -QueryTimeout $queryTimeout
            
        }
        Write-Verbose "Executed your sql command after restoring the database: "
        Write-Verbose $sqlCommandStringToRunAfter
    }

    if( $runAllScriptsThisFolder) {
        if (-not(Test-Path -Path $runAllScriptsThisFolder)) {
            Write-Error "Cannot run all scripts this folder as it does not exist. Folder Name: $runAllScriptsThisFolder"
        }
        else {
            Use-DpSqlScripts -folderName $runAllScriptsThisFolder `
                -sqlServer $sqlServer `
                -userName $userName -password $password `
                -databaseName $dbName
        }
    }

    Write-Output "Restore-DPDb Complete"
}

function Create-DPBlankLoggingDatabase {
    <#
    
    Create a blank logging database ready for use by Enterprise Library
    #>
    [CmdletBinding()]
    param ([string] $loggingDbName, 
        [string] $sqlServer = $defaultSecretConfigs.SqlServerDefaultInstance, 
        [string] $userName = $defaultSecretConfigs.SqlServerUserName, 
        [string] $password = $defaultSecretConfigs.SqlServerUserPassword, 
        [string] $dataFileLocation, 
        [switch] $force
    )

    #some consts
    $queryTimeout = 1500 #for long running queries

    Write-Output "Checking if database $loggingDbName already exists"
    $sql = @"
        declare @dbName nvarchar(255)
        set @dbName = '$loggingDbName'
        IF (EXISTS (SELECT name FROM master.dbo.sysdatabases WHERE ('[' + name + ']' = @dbname OR name = @dbname)))
        begin
            select 1 as AlreadyExists
        end
        else
        begin
            select 0 as AlreadyExists
        end
"@

    $checkResults = Invoke-Sqlcmd `
        -ServerInstance $sqlServer `
        -Username $userName `
        -Password $password `
        -Query $sql `
        -QueryTimeout $queryTimeout
    if ($checkResults.AlreadyExists -eq 1) {
        if (-not ($force)) {
            Write-Output "$loggingDbName already exists. Use the force switch to overwrite if you want. Aborting..."
            return $false
        }
  
        $sql = @"
            USE [master]
            go
            if (db_id('$loggingDbName') is not null)
            begin
                ALTER DATABASE [$loggingDbName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE
            end
            go
            drop database [$loggingDbName]
            go
"@
        Write-Verbose "$loggingDbName already exists. I am going to force drop it"
        Invoke-Sqlcmd `
            -ServerInstance $sqlServer `
            -Username $userName `
            -Password $password `
            -Query $sql `
            -QueryTimeout $queryTimeout
        Write-Verbose "$loggingDbName - force dropped"
    }

    $logicalLoggingDBName = $loggingDbName
    $logicalLoggingDBNameLdf = ("$loggingDbName" + "_log")

    $loggingDbNameLogMDF = Join-Path -Path $dataFileLocation -ChildPath ("$loggingDbName" + ".mdf")
    $loggingDBNameLDF = Join-Path -Path $dataFileLocation -ChildPath ("$loggingDbName" + "_Log.ldf")

    Write-Verbose "Creating logging database with MDF: $loggingDbNameLogMDF"
    Write-Verbose "And LDF: $loggingDBNameLDF"


    $sql = @"

    USE [master]
    GO
    CREATE DATABASE [$loggingDbName] ON  PRIMARY 
    ( NAME = N'$logicalLoggingDBName', FILENAME = N'$loggingDbNameLogMDF' , SIZE = 4160KB , MAXSIZE = UNLIMITED, FILEGROWTH = 1024KB )
     LOG ON 
    ( NAME = N'$logicalLoggingDBNameLdf', FILENAME = N'$loggingDBNameLDF' , SIZE = 1344KB , MAXSIZE = 2048GB , FILEGROWTH = 10%)
    GO

    ALTER DATABASE [$loggingDbName] SET COMPATIBILITY_LEVEL = 90
    GO
    IF (1 = FULLTEXTSERVICEPROPERTY('IsFullTextInstalled'))
    begin
    EXEC [$loggingDbName].[dbo].[sp_fulltext_database] @action = 'enable'
    end
    GO
    ALTER DATABASE [$loggingDbName] SET ANSI_NULL_DEFAULT OFF 
    GO
    ALTER DATABASE [$loggingDbName] SET ANSI_NULLS OFF 
    GO
    ALTER DATABASE [$loggingDbName] SET ANSI_PADDING OFF 
    GO
    ALTER DATABASE [$loggingDbName] SET ANSI_WARNINGS OFF 
    GO
    ALTER DATABASE [$loggingDbName] SET ARITHABORT OFF 
    GO
    ALTER DATABASE [$loggingDbName] SET AUTO_CLOSE OFF 
    GO
    ALTER DATABASE [$loggingDbName] SET AUTO_CREATE_STATISTICS ON 
    GO
    ALTER DATABASE [$loggingDbName] SET AUTO_SHRINK OFF 
    GO
    ALTER DATABASE [$loggingDbName] SET AUTO_UPDATE_STATISTICS ON 
    GO
    ALTER DATABASE [$loggingDbName] SET CURSOR_CLOSE_ON_COMMIT OFF 
    GO
    ALTER DATABASE [$loggingDbName] SET CURSOR_DEFAULT  GLOBAL 
    GO
    ALTER DATABASE [$loggingDbName] SET CONCAT_NULL_YIELDS_NULL OFF 
    GO
    ALTER DATABASE [$loggingDbName] SET NUMERIC_ROUNDABORT OFF 
    GO
    ALTER DATABASE [$loggingDbName] SET QUOTED_IDENTIFIER OFF 
    GO
    ALTER DATABASE [$loggingDbName] SET RECURSIVE_TRIGGERS OFF 
    GO
    ALTER DATABASE [$loggingDbName] SET  DISABLE_BROKER 
    GO
    ALTER DATABASE [$loggingDbName] SET AUTO_UPDATE_STATISTICS_ASYNC OFF 
    GO
    ALTER DATABASE [$loggingDbName] SET DATE_CORRELATION_OPTIMIZATION OFF 
    GO
    ALTER DATABASE [$loggingDbName] SET TRUSTWORTHY OFF 
    GO
    ALTER DATABASE [$loggingDbName] SET ALLOW_SNAPSHOT_ISOLATION OFF 
    GO
    ALTER DATABASE [$loggingDbName] SET PARAMETERIZATION SIMPLE 
    GO
    ALTER DATABASE [$loggingDbName] SET READ_COMMITTED_SNAPSHOT OFF 
    GO
    ALTER DATABASE [$loggingDbName] SET HONOR_BROKER_PRIORITY OFF 
    GO
    ALTER DATABASE [$loggingDbName] SET RECOVERY FULL 
    GO
    ALTER DATABASE [$loggingDbName] SET  MULTI_USER 
    GO
    ALTER DATABASE [$loggingDbName] SET PAGE_VERIFY CHECKSUM  
    GO
    ALTER DATABASE [$loggingDbName] SET DB_CHAINING OFF 
    GO
    USE [$loggingDbName]
    GO

    GO
    SET ANSI_NULLS ON
    GO
    SET QUOTED_IDENTIFIER ON
    GO

    CREATE PROCEDURE [dbo].[InsertCategoryLog]
        @CategoryID INT,
        @LogID INT
    AS
    BEGIN
        SET NOCOUNT ON;

        DECLARE @CatLogID INT
        SELECT @CatLogID FROM CategoryLog WHERE CategoryID=@CategoryID and LogID = @LogID
        IF @CatLogID IS NULL
        BEGIN
            INSERT INTO CategoryLog (CategoryID, LogID) VALUES(@CategoryID, @LogID)
            RETURN @@IDENTITY
        END
        ELSE RETURN @CatLogID
    END

    go

    CREATE PROCEDURE [dbo].[AddCategory]
        -- Add the parameters for the function here
        @CategoryName nvarchar(64),
        @LogID int
    AS
    BEGIN
        SET NOCOUNT ON;
        DECLARE @CatID INT
        SELECT @CatID = CategoryID FROM Category WHERE CategoryName = @CategoryName
        IF @CatID IS NULL
        BEGIN
            INSERT INTO Category (CategoryName) VALUES(@CategoryName)
            SELECT @CatID = @@IDENTITY
        END

        EXEC InsertCategoryLog @CatID, @LogID 

        RETURN @CatID
    END

    GO

    CREATE PROCEDURE [dbo].[ClearLogs]
    AS
    BEGIN
        SET NOCOUNT ON;

        DELETE FROM CategoryLog
        DELETE FROM [Log]
        DELETE FROM Category
    END
    GO

    CREATE PROCEDURE [dbo].[WriteLog]
    (
        @EventID int, 
        @Priority int, 
        @Severity nvarchar(32), 
        @Title nvarchar(256), 
        @Timestamp datetime,
        @MachineName nvarchar(32), 
        @AppDomainName nvarchar(512),
        @ProcessID nvarchar(256),
        @ProcessName nvarchar(512),
        @ThreadName nvarchar(512),
        @Win32ThreadId nvarchar(128),
        @Message nvarchar(1500),
        @FormattedMessage ntext,
        @LogId int OUTPUT
    )
    AS 

        INSERT INTO [Log] (
            EventID,
            Priority,
            Severity,
            Title,
            [Timestamp],
            MachineName,
            AppDomainName,
            ProcessID,
            ProcessName,
            ThreadName,
            Win32ThreadId,
            Message,
            FormattedMessage
        )
        VALUES (
            @EventID, 
            @Priority, 
            @Severity, 
            @Title, 
            @Timestamp,
            @MachineName, 
            @AppDomainName,
            @ProcessID,
            @ProcessName,
            @ThreadName,
            @Win32ThreadId,
            @Message,
            @FormattedMessage)

        SET @LogID = @@IDENTITY
        RETURN @LogID


    GO

    CREATE TABLE [dbo].[Category](
        [CategoryID] [int] IDENTITY(1,1) NOT NULL,
        [CategoryName] [nvarchar](64) NOT NULL,
     CONSTRAINT [PK_Categories] PRIMARY KEY CLUSTERED 
    (
        [CategoryID] ASC
    )WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
    ) ON [PRIMARY]

    GO

    CREATE TABLE [dbo].[CategoryLog](
        [CategoryLogID] [int] IDENTITY(1,1) NOT NULL,
        [CategoryID] [int] NOT NULL,
        [LogID] [int] NOT NULL,
     CONSTRAINT [PK_CategoryLog] PRIMARY KEY CLUSTERED 
    (
        [CategoryLogID] ASC
    )WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
    ) ON [PRIMARY]

    GO

    CREATE TABLE [dbo].[Log](
        [LogID] [int] IDENTITY(1,1) NOT NULL,
        [EventID] [int] NULL,
        [Priority] [int] NOT NULL,
        [Severity] [nvarchar](32) NOT NULL,
        [Title] [nvarchar](256) NOT NULL,
        [Timestamp] [datetime] NOT NULL,
        [MachineName] [nvarchar](32) NOT NULL,
        [AppDomainName] [nvarchar](512) NOT NULL,
        [ProcessID] [nvarchar](256) NOT NULL,
        [ProcessName] [nvarchar](512) NOT NULL,
        [ThreadName] [nvarchar](512) NULL,
        [Win32ThreadId] [nvarchar](128) NULL,
        [Message] [nvarchar](1500) NULL,
        [FormattedMessage] [ntext] NULL,
     CONSTRAINT [PK_Log] PRIMARY KEY CLUSTERED 
    (
        [LogID] ASC
    )WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
    ) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

    GO
    SET IDENTITY_INSERT [dbo].[Category] ON 

    GO

    INSERT [dbo].[Category] ([CategoryID], [CategoryName]) VALUES (1, N'General')
    GO

    SET IDENTITY_INSERT [dbo].[Category] OFF

    GO

    CREATE NONCLUSTERED INDEX [ixCategoryLog] ON [dbo].[CategoryLog]
    (
        [LogID] ASC,
        [CategoryID] ASC
    )WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
    GO

    ALTER TABLE [dbo].[CategoryLog]  WITH CHECK ADD  CONSTRAINT [FK_CategoryLog_Category] FOREIGN KEY([CategoryID])
    REFERENCES [dbo].[Category] ([CategoryID])
    GO

    ALTER TABLE [dbo].[CategoryLog] CHECK CONSTRAINT [FK_CategoryLog_Category]
    GO

    ALTER TABLE [dbo].[CategoryLog]  WITH CHECK ADD  CONSTRAINT [FK_CategoryLog_Log] FOREIGN KEY([LogID])
    REFERENCES [dbo].[Log] ([LogID])
    GO

    ALTER TABLE [dbo].[CategoryLog] CHECK CONSTRAINT [FK_CategoryLog_Log]
    GO

    USE [$loggingDbName]
    GO
    CREATE USER [NexusUser] FOR LOGIN [NexusUser]
    GO
    USE [$loggingDbName]
    GO
    EXEC sp_addrolemember N'db_datareader', N'NexusUser'
    GO
    USE [$loggingDbName]
    GO
    EXEC sp_addrolemember N'db_datawriter', N'NexusUser'
    GO
    USE [$loggingDbName]
    GO
    EXEC sp_addrolemember N'db_owner', N'NexusUser'
    GO


    USE [master]
    GO
    ALTER DATABASE [$loggingDbName] SET  READ_WRITE 
    GO

"@

    Invoke-Sqlcmd `
        -ServerInstance $sqlServer `
        -Username $userName `
        -Password $password `
        -Query $sql `
        -QueryTimeout $queryTimeout

    Write-Output "Create-DPBlankLoggingDatabase Complete"
}


function Restore-DpMostRecentDbBackup {
    <#
    .SYNOPSIS
    Use the file filter to find the most recent backup database (.bak) file and restore it
    #>
    [CmdletBinding(SupportsShouldProcess=$True)]
    param(
        [string] $dbName = $defaultSecretConfigs.SqlDefaultDatabaseName, 
        [string] $workingFolder, 
        [string] $logFolderName = "logs", 
        [string] $sqlServer = $defaultSecretConfigs.SqlServerDefaultInstance, 
        [string] $username = $defaultSecretConfigs.SqlServerUserName, 
        [string] $password = $defaultSecretConfigs.SqlServerUserPassword, 
        [string] $dataLocation = $defaultSecretConfigs.SqlDefaultDataLocation, 
        [string] $postUpdateScriptsFolder, 
        [string] $postUpdateOptimiseDatabaseScriptsFolder, 
        [switch] $shrinkOnRestore = $False, 
        [string] $logicalFileName = $defaultSecretConfigs.SqlDefaultDatabaseName, 
        [string] $logicalLogName = ($defaultSecretConfigs.SqlDefaultDatabaseName + "_log")
    )

    if (-not ($workingFolder)) {
        $workingFolder = Get-Location -PSProvider FileSystem
    }

    $queryTimeout = [int] 1200 #make it a large number as some restores can take time

    $fileFilter = "*$dbName*.bak"
    $mostRecentBak = Get-ChildItem -Path $workingFolder -File -Filter $fileFilter | `
        sort -Property "LastWriteTime" -Descending | select -First 1

    $mostRecentBakFullPath = Join-Path -Path $workingFolder -ChildPath $mostRecentBak
    if (-not $mostRecentBak -or -not (Test-Path -Path $mostRecentBakFullPath)) {
        Write-Error "Could not find a most recent BAK backup file of database $dbName in folder $workingFolder"
        return
    }
    Write-Verbose "Found backup file $mostRecentBakFullPath"
    if ($PSCmdlet.ShouldProcess("$mostRecentBakFullPath as $dbName", "Restore-DPDb")) {
        Restore-DPDb -dbName $dbName -workingFolder $workingFolder `
            -databaseFileName $mostRecentBakFullPath `
            -sqlServer $sqlServer -userName $username -password $password `
            -dataLocation $dataLocation `
            -logicalFileName $logicalFileName `
            -logicalLogName $logicalLogName
    }

    Write-Output "Restore-DpMostRecentDbBackup Complete"
}



