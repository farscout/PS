<#
.DESCRIPTION
A library of Azure support calls with common specific values
#>


#some common constants
$defaultAzureRegion = "Australia East" #you could also try West Europe, East Asia


function Ensure-ServiceBusDll {
    <#
    .DESCRIPTION
    Load the Azure dll to give us more granular Azure operations than just the issue Azure Powershells
    #>
    $dll = "Microsoft.ServiceBus.dll"
    #msdn docs on the servicebus namespace
    #https://msdn.microsoft.com/library/azure/microsoft.servicebus.aspx?f=255&MSPPError=-2147217396
    try
    {
        Write-Output "Adding the $dll assembly to the script..."
        
        $packagesFolder = Join-Path $PSScriptRoot "dll"
        $assembly = Get-ChildItem $packagesFolder -Include $dll -Recurse
        Add-Type -Path $assembly.FullName

        Write-Output "The $dll assembly has been successfully added to the script."
        $True
    }
    catch [System.Exception]
    {
        Write-Error "Could not add the $dll assembly to the script."
        $False
    }
}


function Get-ServiceBusConnectionString {
    <#
    .DESCRIPTION
    Just return the connectionstring for use in subscriptions and creating clients
    #>
    param($serviceBusNamespace)
    $ns = Get-AzureSBNamespace -Name $serviceBusNamespace
    $ns.ConnectionString
}

function Create-DpeServiceBusSASKey {
    <#
    .DESCRIPTION
    Create or get an SAS key against the service bus and return its key for use with clients
    .PARAMETER serviceBusNamespace
    The name of your service bus
    .PARAMETER ruleName
    The name to give your rule
    .PARAMETER permission
    list of permissions, eg $("Manage", "Listen", "Send")
    or $("Listen", "Send")
    or $("Listen")

    .EXAMPLE
    New-AzureSBAuthorizationRule -Name "MyRule" -Namespace $AzureSBNameSpace 
      -Permission $("Manage", "Listen", "Send") -EntityName $QName -EntityType Queue

    .NOTES
    New-AzureSBAuthorizationRule works only when I creating a namespace level SAS policy. 
    Using -EntityName and -EntityType params creating an entity level SAS policy gives 
    an object reference not set error. 
    Bug in the MS Powershell cmdlet - so just create at ServiceBus level (meh).
    #>
    [CmdletBinding()]
    param($serviceBusNamespace, $ruleName, $permission=$("Manage", "Listen", "Send"))
    $ruleDetails = New-AzureSBAuthorizationRule -Name $ruleName -Namespace $serviceBusNamespace -Permission $permission 
    $ruleDetails.ConnectionString
}

function Select-DpeServiceBus {
	<#
    .DESCRIPTION
    Create the service bus. Default is to create in Australia East region. Some other regions are: West Europe, East Asia
    .PARAMETER force
    should the service bus be created if it does not already exist
    #>

    param($location = $defaultAzureRegion, $serviceBusNamespace, [switch] $force)
	$ns = Get-AzureSBNamespace -Name $serviceBusNamespace

    if ($ns) {
        $ns
        return
    }

	if (-not $ns -and $force) {
		Write-Output "Service Bus namespace $serviceBusNamespace does not already exist, forcing creation"
		Write-Output "Creating the [$serviceBusNamespace] namespace in the [$Location] region..."
	    New-AzureSBNamespace -Name $serviceBusNamespace -Location $Location -CreateACSNamespace $false -NamespaceType Messaging
	    $ns = Get-AzureSBNamespace -Name $serviceBusNamespace
	    Write-Output "The [$serviceBusNamespace] namespace in the [$Location] region has been successfully created."
	}

	$ns
}

function Create-DpeSbTopic {
	param($serviceBusNamespace, $topicName, $defaultMessageTimeToLiveMinutes = 10, [switch] $forceRecreate)

    $t = Ensure-ServiceBusDll
    if (-not $t) {
        Write-Error 'Could not ensure the service bus dll was loaded. Stopping'
        return
    }


    $ns = Select-DpeServiceBus -serviceBusNamespace $serviceBusNamespace -force
    if (-not $ns) {
        Write-Error "Could not select the Service Bus $serviceBusNamespace. Stopping."
        return
    }
    $nsManager = [Microsoft.ServiceBus.NamespaceManager]::CreateFromConnectionString($ns.ConnectionString);
	
    if ($nsManager.TopicExists($topicName))
    {
        Write-Output "The $topicName topic already exists in the $serviceBusNamespace namespace." 
        if ($forceRecreate) {
            #flush the existing and go on
            Write-Output "Flushing existing as you said forceRecreate"
            $nsManager.DeleteTopic($topicName)
            Write-Output "Deleted existing Topic $topicName"
        }
        else {
            return
        }
    }

    Write-Output "Creating $topicName Topic in the $serviceBusNamespace namespace"
    $topicDescription = (New-Object -TypeName Microsoft.ServiceBus.Messaging.TopicDescription -ArgumentList $topicName)
    if ($defaultMessageTimeToLiveMinutes) {
        $topicDescription.DefaultMessageTimeToLive = [System.TimeSpan]::FromMinutes($defaultMessageTimeToLiveMinutes)
    }
  
    $nsManager.CreateTopic($topicDescription);
    Write-Output "Created $topicName Topic in the $serviceBusNamespace namespace"
}

function Create-DpeSbSubscription {
    param($serviceBusNamespace, $topicName, $subscriptionName, $messageTimeToLiveMinutes)

    $t = Ensure-ServiceBusDll
    if (-not $t) {
        Write-Error "Could not ensure the service bus dll was loaded. Stopping"
        return
    }

    $ns = Select-DpeServiceBus -serviceBusNamespace $serviceBusNamespace -force
    if (-not $ns) {
        Write-Error "Could not select the Service Bus $serviceBusNamespace. Stopping."
        return
    }
    $nsManager = [Microsoft.ServiceBus.NamespaceManager]::CreateFromConnectionString($ns.ConnectionString);
    if ($nsManager.SubscriptionExists($topicName, $subscriptionName)) {
        Write-Output "Subscription $subscriptionName already exists on Topic $topicName."
        return
    }

    $subDescription = (New-Object -TypeName Microsoft.ServiceBus.Messaging.SubscriptionDescription -ArgumentList $topicName, $subscriptionName)

    #$nsManager.CreateSubscription($topicName, $subscriptionName)
    if ($messageTimeToLiveMinutes) {
        $subDescription.DefaultMessageTimeToLive = [System.TimeSpan]::FromMinutes($messageTimeToLiveMinutes)
    }
    $nsManager.CreateSubscription($subDescription)

    Write-Output "Subscription $subscriptionName created on Topic $topicName"
}


function DpeTestit {
    #just a quick test so you do not have to type the whole command
    Create-DpeSbTopic -serviceBusNamespace 'realtime-preprod' -topicName 'tester1' -defaultMessageTimeToLiveMinutes 10
    #create a subscription on that topic
    Create-DpeSbSubscription -serviceBusNamespace 'realtime-preprod' -topicName 'tester1' `
        -subscriptionName 'TestSub1' -messageTimeToLiveMinutes 10
}
