$PublicIPService = "https://api.ipify.org"

<#
Script Usage 
-------------------------------------------------------------
To execute this script, open a PowerShell prompt, navigate to the directory where the script is saved, and execute the following command:
 .\get_networkinfo.ps1

NOTE: Incase you get an error executing this script, execute one of the following command within PowerShell 
+ Only allows locally created scripts and signed scripts from the internet:
 Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
+ Allow all scripts for the current session (use with caution):
 Set-ExecutionPolicy -Scope Process Unrestricted
#>

# Display error messages
function Log-Error{
	param([string]$Message)
	Write-Error "ERROR: $Message"
}

# IP Class Function
function Get-IPClass{
	param([string]$IPAddress)
	
	try {
		$FirstOctect = [int]($IPAddress.Split('.')[0])
        if ($FirstOctect -ge 1 -and $FirstOctect -le 126) {
            return "Class A"
        }
        if ($FirstOctect -ge 128 -and $FirstOctect -le 191) {
            return "Class B"
        }
        if ($FirstOctect -ge 192 -and $FirstOctect -le 223) {
            return "Class C"
        }
        return "Reserved/Special"
	} catch {
        return "Unknown"
    }
}

# Public IP Address
function Get-PublicIPAddress{
    $PublicIP = "N/A (Internet Required)"
    try {
        $PublicIP = Invoke-RestMethod -Uri $PublicIPService - TimeoutSec 5
    } catch {
        Log-Error "Failed to retrieve Public IP address: $($_.Exception.Message)"
    }
    return $PublicIP
}

# DNS Server IP Address
function Get-DNSServer{
    $DNSServer = Get-DNSClientServerAddress -AddressFamily IPv4 | Select-Object -ExpandProperty ServerAddresses -Unique
    $DNSServers = $DNSServer -join ", "
}

Write-Host "INFO - Gathering all local network interface details..."
Write-Host "INFO - Checking for DNS Server Address..."
Write-Host "INFO - Retrieving public IP address from external services...`n"

# Main Script Section
Write-Host "================================================================="
Write-Host "                    NETWORK INFORMATION REPORT"
Write-Host "=================================================================`n"

Write-Host "## Local Network Interfaces (NICs) ##"
Write-Host "-----------------------------------------------------"
try {
    # Get all network configs that have an IPv4 address assigned (and not loopback)
    $AllConfigs = Get-NetIPConfiguration | Where-Object {
        $_.IPv4Address -ne $null -and $_.InterfaceAlias -ne "Loopback Psuedoe-Interfaces 1"
    }

    if ($AllConfigs.Count -eq 0) {
        Write-Host "No active IPv4 network interfaces found"
    }

    foreach ($Config in $AllConfigs) {
        $IPAddress = $Config.IPv4Address.IPAddress
        $PrefixLength = $Config.IPv4Address.PrefixLength

        $IPClass = Get-IPClass -IPAddress $IPAddress

        Write-Host "**Interface:** : **$($Config.InterfaceAlias)**"
        Write-Host "Local IP Address   : $IPAddress"
        Write-Host "Subnet Mask /CIDR  : /$PrefixLength"
        Write-Host "Network Range      : $IPAddress/$PrefixLength"
        Write-Host "IP Class           : $IPClass"

        # Check if specific DNS set for this interface (separate from system DNS)
        $InterfaceDNS = Get-DnsClientServerAddress -InterfaceIndex $Config.InterfaceIndex -AddressFamily IPv4 | Select-Object -ExpandProperty ServerAddresses -Unique
        if ($InterfaceDNS.Count -gt 0) {
            Write-Host "Interface DNS      : $($InterfaceDNS -join ',') "
        }
        Write-Host "`n"
    }

} catch {
    Log-Error "A critical error occurred while processing NICs: $($_.Exception.Message)"
}
Write-Host "-----------------------------------------------------`n"

Write-Host "## Global Network Information ##"
Write-Host "-----------------------------------------------------"
Write-Host "Public Internet IP Address: $(Get-IPClass)"
Write-Host "DNS Server IP Address     : $(Get-DNSServer)"
Write-Host "-----------------------------------------------------`n"

Write-Host "=================================================================`n"
Write-Host "INFO - Network information gathering complete."
