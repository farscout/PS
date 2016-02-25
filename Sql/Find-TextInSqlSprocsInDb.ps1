<#
.SYNOPSIS
Find text within the sprocs on a sql server database
#>

[CmdletBinding()]
param($databaseName, $sqlServer, $userName, $password, $searchText)

$sql = @"
select o.Name, o.type_desc, c.text
from sys.objects o

join sys.syscomments c
    on o.object_id = c.id

where 
    o.type = 'P'
    c.text like '%$searchText%'
"@

$curr = get-location -psprovider filesystem
import-module SQLPS
set-location $curr

$queryTimeout = 1500 #for long running queries

$result = Invoke-Sqlcmd `
    -ServerInstance $sqlServer `
    -Username $userName `
    -Password $password `
    -Query $sql `
    -QueryTimeout $queryTimeout

$result
