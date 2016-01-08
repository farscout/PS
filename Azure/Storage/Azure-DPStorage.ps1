<# 
.DESCRIPTION 
Library of Azure Storage operations

#>

function Get-DPAzureStorageAccount {
    [CmdletBinding()]
    param ($StorageAccountName, $azureLocation = "Australia East", [switch]$force)

    if ((Get-AzureStorageAccount | ? { $_.StorageAccountName -eq $StorageAccountName }).Count -eq 0) {
        if ($force) {
            New-AzureStorageAccount -StorageAccountName $StorageAccountName -Location $azureLocation 
        }
        else {
            Write-Error "StorageAccount $StorageAccountName does not exist"
            return
        }
    }
    Get-AzureStorageAccount -StorageAccountName $StorageAccountName
}


function Get-DPFromAzureStorage {
    <#
    .DESCRIPTION
    Get all files from a storage container and copy them locally
    #>
    [CmdletBinding()]
    param($StorageAccountName, $containerName, $destinationFolder, [switch]$force)

    if ($force) {
        Write-Verbose "Flushing any existing files because you said force"
        Get-ChildItem -Path $destinationFolder | Remove-Item -Recurse -Force 
    }

    $storageAccountKey = Get-AzureStorageKey $storageAccountName | %{ $_.Primary }
    $context = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $storageAccountKey
    $files = Get-AzureStorageBlob -Context $context -Container $containerName
    foreach ($file in $files) {
         #fq name represents fully qualified name
         $fqName = Join-Path $destinationFolder $file.Name
         Get-AzureStorageBlobContent -Blob $file.Name -Container $ContainerName `
            -Destination $fqName -Context $context -Force
         Write-Verbose ($file.Name + " downloaded from Azure Storage")
    }
}

function Send-DPToAzureStorage {
    [CmdletBinding()]
    param($StorageAccountName, $containerName, $sourceFolder, [switch]$force)

    $storageAccount = Get-DPAzureStorageAccount -StorageAccountName $StorageAccountName -force:$force
    $storageAccountKey = Get-AzureStorageKey $storageAccountName | %{ $_.Primary }
    $context = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $storageAccountKey

    #check if the storage container already exists
    $container = Get-AzureStorageContainer | ? { $_.Name -eq $containerName }
    if (-not $container) {
        Write-Verbose "Container $containerName does not already exist - creating..."
        $container = New-AzureStorageContainer $ContainerName -Permission Container -Context $context
    }

    $files = Get-ChildItem $sourceFolder -force

    # iterate through all the files and start uploading data
    foreach ($file in $files) {
         $fqName = Join-Path $uploadFolder $file.Name
         Set-AzureStorageBlobContent -Blob $file.Name -Container $ContainerName -File $fqName -Context $context -Force
         Write-Verbose ($file.Name + " uploaded to Azure Storage")
    }
}


