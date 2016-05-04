#browse certs
Get-ChildItem cert:\currentuser\My

Get-ChildItem cert:\currentuser\My | Format-Table Thumbprint, FriendlyName, Subject  -AutoSize

Get-ChildItem cert:\LocalMachine