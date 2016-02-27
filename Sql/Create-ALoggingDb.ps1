

<# .SYNOPSIS 
Create a logging database using the passed in name

.PARAMETER loggingDbName 
the name of the logging database to Create
.PARAMETER sqlServer 
the name of the sql server to create the logging db on
.PARAMETER userName 
the username to login to the sql server on
.PARAMETER password 
the password to connect to the sql server with
.PARAMETER dataFileLocation 
the location to create the mdf and ldf files

.EXAMPLE 
.\Create-ALoggingDb.ps1 -loggingDbName "MyLogDb_Log" -sqlServer "." -userName "sa" -password "secretSoThere" -dataFileLocation "D:\SQL-DB"

#>
[CmdletBinding()]
param ([string] $loggingDbName, 
    [string] $sqlServer, 
    [string] $userName, 
    [string] $password, 
    [string] $dataFileLocation)

Write-Output "Creating logging database $loggingDbName"

$logicalLoggingDBName = $loggingDbName
$logicalLoggingDBNameLdf = ("$loggingDbName" + "_log")

$loggingDbNameLogMDF = Join-Path -Path $dataFileLocation -ChildPath ("$loggingDbName" + ".mdf")
$loggingDBNameLDF = Join-Path -Path $dataFileLocation -ChildPath ("$loggingDbName" + "_Log.ldf")

Write-Output "Creating logging database with MDF: $loggingDbNameLogMDF"
Write-Output "And LDF: $loggingDBNameLDF"

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

$curr = get-location -psprovider filesystem
import-module SQLPS
set-location $curr

$queryTimeout = 1500 #for long running queries

Invoke-Sqlcmd `
    -ServerInstance $sqlServer `
    -Username $userName `
    -Password $password `
    -Query $sql `
    -QueryTimeout $queryTimeout

Write-Output "Complete"
