<#                       
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 |w|w|w|.|r|l|e|v|c|h|e|n|k|o|.|c|o|m|
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+                                                                                                    

::RRAS installation (PowerShell DSC)
                                                                                             
 #>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "")]
param ()
#RRAS Configuration

$netbios = "rlevchenko" + '-' + $args[0]
$pcname = "rl" + $args[0] + '-' + "rras01"
$pwd = ConvertTo-SecureString "Pass1234" -AsPlainText -Force
$localcred = New-Object System.Management.Automation.PSCredential ("Administrator", $pwd)

#Gathering information about NIC adapters

#Internal NIC 
$intnic = Get-NetIPAddress -AddressFamily IPv4 | ? { $_.Ipaddress -match "x.x.*" }
$intpart = ($intnic.IpAddress).split(".")[3]
$addressint = ($intnic.IpAddress).TrimEnd("$intpart")
$internalip = $addressint + '1'
Rename-NetAdapter -NewName Internal -Name $intnic.InterfaceAlias
#Infra NIC
$infranic = Get-NetIPAddress -AddressFamily IPv4 | ? { $_.Ipaddress -match "x.x.x.*" }
$infrapart = ($infranic.IpAddress).split(".")[3]
$addressinfra = ($infranic.IpAddress).TrimEnd("$infrapart")
$infraip = $addressinfra + (10 + $args[0])
Rename-NetAdapter -NewName Infra -Name $infranic.InterfaceAlias
#Exernal Nic
$extnic = Get-NetIPAddress -AddressFamily IPv4 | ? { $_.Ipaddress -notmatch "x.x.x.*" -and $_.Ipaddress -notmatch "x.x.1.*" -and $_.InterfaceAlias -notmatch "Loopback*" }
$extip = $args[1]
$extgw = $args[2]
Rename-NetAdapter -NewName External -Name $extnic.InterfaceAlias

configuration RRAS
{
    Import-DscResource -ModuleName xNetworking
    Import-DscResource -ModuleName xComputerManagement

    Node $AllNodes.Nodename
    {
        LocalConfigurationManager {            
            ConfigurationMode  = 'ApplyOnly'
            RebootNodeIfNeeded = $true 
                      
        }  
        xComputer PCName #Set PC Name
     
        {
            Name          = $pcname
            WorkgroupName = "Workgroup"
        }
         
        xDhcpClient DisabledDhcpClient #Disable DHCP 
        {
            State          = 'Disabled'
            InterfaceAlias = "Internal"
            AddressFamily  = "IPv4"
        }

        xIPAddress NewIPAddressInt #Set Static IPv4 on Internal
        {
            IPAddress      = $internalip
            InterfaceAlias = "Internal"
            SubnetMask     = 24
            AddressFamily  = "IPV4"
        }
        xIPAddress NewIPAddressExt #Set Static IPv4 on External
        {
            IPAddress      = $extip
            InterfaceAlias = "External"
            SubnetMask     = 24
            AddressFamily  = "IPV4"
        }
        xDefaultGatewayAddress ExtGW #Set GW address on external
        {
            Address        = $extgw
            InterfaceAlias = "External"
            AddressFamily  = "IPv4" 

        }

        xIPAddress NewIPAddressInfra #Set Static IPv4 on Infrastructure nic
        {
            IPAddress      = $infraip
            InterfaceAlias = "Infra"
            SubnetMask     = 24
            AddressFamily  = "IPV4"
        }
        
        WindowsFeature Routing {             
            Ensure = "Present"             
            Name   = "Routing"
                        
        }  
        WindowsFeature Tools {             
            Ensure               = "Present"             
            Name                 = "RSAT-RemoteAccess"
            IncludeAllSubFeature = $true
                        
        }      
               

    }

}
$ConfigData = @{
    AllNodes = @(

        @{
            Nodename                    = $pcname
            PSDscAllowPlainTextPassword = $true
        }
    )
}

#Creating mof files
RRAS -configurationData $configdata

#Sets LCM
Set-DSCLocalConfigurationManager -Path .\RRAS –Verbose 

#Starts DSC
Start-DscConfiguration -Wait -Force -Verbose -Path .\RRAS -Credential $localcred
