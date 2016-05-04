

[CmdletBinding()]
param($azureStorageAccountName="realtimestorageacc",
    $azureServiceLocation = "Australia East",
    [switch] $remove,
    [switch] $force)

$storeAcc = Get-AzureStorageAccount -StorageAccountName $azureStorageAccountName -ErrorAction SilentlyContinue
if (-not $storeAcc) {
    Write-Output "StorageAccount $azureStorageAccountName does not exist - creating..."

    New-AzureStorageAccount -StorageAccountName $azureStorageAccountName `
        -Label $azureStorageAccountName `
        -Location $azureServiceLocation `
        -Type "Standard_LRS" #Locally Redundant, cheapest at 3.06AUD per 100GIG
    Write-Output "New Storage Account created named $azureStorageAccountName"
}
else {
    Write-Output "$azureStorageAccountName already exists"
}

$storageKeyDetails = Get-AzureStorageKey -StorageAccountName $azureStorageAccountName
$primaryStorageKey = $storageKeyDetails.Primary
$storageAccountConnectionString = "DefaultEndpointsProtocol=https;AccountName=$azureStorageAccountName;AccountKey=$primaryStorageKey"
Write-Output "StorageAccount ConnectionString: $storageAccountConnectionString"

if ($remove) {
    Write-Output "removing storage account $azureStorageAccountName"
    if (-not $force) {
        Write-Output "removing a storage account is so serious, that you must also use the force switch - and you did not, so not doing anything."
        return
    }
    Remove-AzureStorageAccount -StorageAccountName $azureStorageAccountName
    Write-Output "$azureStorageAccountName removed"
}

Write-Output (($MyInvocation.MyCommand.Name) + " complete")
