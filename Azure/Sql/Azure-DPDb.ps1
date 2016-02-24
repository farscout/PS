<#
.SYNOPSIS
Provides utility functions for working with Azure databases
#>

<# A json file to provide secret creds and settings not co-located with the
powershell implementation scripts - replace with your own json of the form
{
    "AzureSqlServerAdminLogin" : "LoginName",
    "AzureSqlServerAdminPassword" : "Password",
    "AzureLocation" : "Australia East",
    "ExternalIPPrimary" : "some ip number",
    "ExternalIPAlternate" : "some alternate ip number"
}
#>

$defaultSecretConfigFile = "C:\G\a\configs\default-azure-ps-config.json"
$defaultConfig = Get-Content -Path $defaultSecretConfigFile | ConvertFrom-Json


function Create-DPAzureSqlDatabase {
    [CmdLetBinding()]
    param($databaseName, 
        $azureLocation = $defaultConfig.AzureLocation, 
        $azureSqlAdminLoginName = $defaultConfig.AzureSqlServerAdminLogin,
        $azureSqlAdminPassword = $defaultConfig.AzureSqlServerAdminPassword)

    $foundDb = Get-AzureSqlDatabaseServer | Select ServerName | `
        % { Get-AzureSqlDatabase -ServerName $_.ServerName  | ? { $_.Name -eq $databaseName }}
    if (-not $foundDb) {
        $newSqlServer = New-AzureSqlDatabaseServer -AdministratorLogin $azureSqlAdminLoginName `
            -AdministratorLoginPassword $azureSqlAdminPassword -Force -Location $azureLocation
        Write-Verbose ("created new sql database server " + $newSqlServer.ServerName)

        #https://msdn.microsoft.com/en-us/library/dn546722.aspx
        $foundDb = New-AzureSqlDatabase -ServerName $newSqlServer.ServerName `
            -DatabaseName $databaseName -Force
        Write-Verbose "new sql database $databaseName created"

        Set-DPAzureFirewallRuleDefaultsByDbName -databaseName $databaseName
    }

    if (-not $foundDb) {
        Write-Error "Could not find or create database $databaseName"
        return
    }
    Write-Verbose ("Database " + $foundDb.Name  + " ready")
}

function Invoke-DPSqlAzure {
    <#
    .SYNOPSIS
    Exec some sql against an azure sql database
    .PARAMETER sql
    optional - set this value to run an sql string against the database
    .PARAMETER File
    optional - set this value to run an sql file against the database

    #>

    [CmdLetBinding()]
    param([Parameter(Mandatory=$True,Position=0)] $databaseName, 
        $sql,
        $File,
        $azureSqlAdminLoginName = $defaultConfig.AzureSqlServerAdminLogin,
        $azureSqlAdminPassword = $defaultConfig.AzureSqlServerAdminPassword)
    
    $queryTimeout = 1500   
    $currentLocation = Get-Location -PSProvider FileSystem
    import-module sqlps
    Set-Location -Path $currentLocation #so we don't end up in the sql filesystem (annoying when importing sqlps)

    $serverName = Get-AzureSqlServerByDbName -databaseName $databaseName

    $sqlServer = "$serverName.database.windows.net"
    if ($File) {
        $resultFile = Invoke-SqlCmd -InputFile $File `
            -ServerInstance $sqlServer `
            -database $databaseName `
            -Username $azureSqlAdminLoginName `
            -Password $azureSqlAdminPassword `
            -QueryTimeout $queryTimeout
        $resultFile   
    }
    if ($sql) {
        $resultSql = Invoke-SqlCmd -Query $sql `
            -ServerInstance $sqlServer `
            -database $databaseName `
            -Username $azureSqlAdminLoginName `
            -Password $azureSqlAdminPassword `
            -QueryTimeout $queryTimeout
        $resultSql
    }
}

function Get-DpAzureSqlDbConnectionStringByDbName {
    <#
    .SYNOPSIS
    Get the connection string to the sql server with the databaseName in it
    #>
    [CmdletBinding()]
    param ([Parameter(Mandatory=$True,Position=0)] $databaseName, 
    $azureSqlAdminLoginName = $defaultConfig.AzureSqlServerAdminLogin,
    $azureSqlAdminPassword = $defaultConfig.AzureSqlServerAdminPassword)

    $serverName = Get-AzureSqlServerByDbName -databaseName $databaseName 
    $connectionString = "Server=tcp:$serverName.database.windows.net;Database=$databaseName;User ID=$azureSqlAdminLoginName@$serverName;Password=$azureSqlAdminPassword;Trusted_Connection=False;Encrypt=True;"
    $connectionString
}

function Get-AzureSqlServerByDbName {
    <#
    .SYNOPSIS
    Return the first sql server that contains the database named $databaseName
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory=$True,Position=0)] $databaseName)
    $serverName = ""
    $sqlServers = Get-AzureSqlDatabaseServer | select ServerName
    foreach ($srv in $sqlServers.ServerName) {
        Write-Verbose "Checking server $srv for database $databaseName"
        if (Get-AzureSqlDatabase -ServerName $srv | ? { $_.Name -eq $databaseName }) {
            $serverName = $srv
        }
    }
    $serverName
}

function Get-MyExternalIp {
    [CmdLetBinding()]
    param()
    $myExternalIpRequest = Invoke-WebRequest ifconfig.me/ip
    $ip = $myExternalIpRequest.Content.Trim()
    Write-Verbose "Got your external IP of $ip"
    $ip
}

function Set-DPAzureFirewallRuleDefaultsByDbName {
    <#
    .SYNOPSIS
    Use the default primary and alternate external IP to set a firewall rule on the
    sql server for the passed in database name
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory=$True,Position=0)] $databaseName)

    $serverName = Get-AzureSqlServerByDbName -databaseName $databaseName

    New-AzureSqlDatabaseServerFirewallRule `
        -StartIPAddress $defaultConfig.ExternalIPPrimary `
        -EndIPAddress $defaultConfig.ExternalIPPrimary `
        -RuleName "DefaultExternalIPPrimary" -ServerName $serverName

    New-AzureSqlDatabaseServerFirewallRule `
        -StartIPAddress $defaultConfig.ExternalIPAlternate `
        -EndIPAddress $defaultConfig.ExternalIPAlternate `
        -RuleName "DefaultExternalIPAlternate" -ServerName $serverName
}

function Set-DPAzureDbFirewallRuleByDbName {
    <#
    .SYNOPSIS
    Create a firewall rule on the sql server holding the database name
    If the firewall named rule already exists, yet the ip is different, remove and re-add with the passed in
    or current IP
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory=$True,Position=0)] $databaseName, 
        [Parameter(Position=1)] $ip, 
        $firewallRuleName = "DominosInternal")
    if (-not $ip) {
        $ip = Get-MyExternalIp
        Write-Verbose "ip param not passed in, using your external IP of $ip"
    }

    #find the sql server the database is on
    $serverName = Get-AzureSqlServerByDbName -databaseName $databaseName

    #do we have an existing firewall rule
    $existingFwRule = Get-AzureSqlDatabaseServerFirewallRule -ServerName $serverName | `
        ? { $_.RuleName -eq $firewallRuleName }

    if ($existingFwRule) {
        if ($existingFwRule.StartIPAddress -ne $ip) {
            $existingDifferentIp = $existingFwRule.StartIPAddress
            Write-Verbose "Existing rule found with ip $existingDifferentIp different IP"
            Remove-AzureSqlDatabaseServerFirewallRule -ServerName $serverName -RuleName $existingFwRule.RuleName
            Write-Verbose ("Existing rule " + $existingFwRule.RuleName + " removed")
        }
        else {
            Write-Verbose "Rule $firewallRuleName already existing and pointing to the correct ip $ip"
            return
        }
    }

    New-AzureSqlDatabaseServerFirewallRule -StartIPAddress $ip -EndIPAddress $ip `
        -RuleName $firewallRuleName -ServerName $serverName
    Write-Verbose "Firewall rule $firewallRuleName created and pointing to ip $ip"
}

function Clear-DPAzureAllSqlDatabaseServers {
    [CmdLetBinding()]
    param([switch] $force)
    if (-not $force) {
        Write-Error "This method is so serious and will delete ALL your sql database servers and ALL their databases, that you must always call it with the -force param"
        return
    }
    Get-AzureSqlDatabaseServer | % { Remove-AzureSqlDatabaseServer -ServerName $_.ServerName  -Force }
}

