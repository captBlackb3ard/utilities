#!/bin/bash

: "
Script Usage
--------------------------------------------------
# Execute the following command to make this script executable:
- chmod +x network_bash.sh

# Execute the script:
- ./network_bash.sh


# NOTE: 
+ All logging and error information stored in the 'network_info.log' file within the same directory as this script
+ Ideally this script does not need to run as root or adminstrator.
"

PUBLIC_IP_SERVICE="https://api.ipify.org"

# Function to display error messages & exit
log_error(){
	echo "ERROR: $1" >&2
}

# Logging Config
LOG_FILE="$(pwd)/network_bash.log"
# Send all stdout/err to console & log file
exec > >(tee -a "$LOG_FILE") 2>&1


get_ip_class(){
	local ip=$1
	local first_octect=$(echo $ip | cut -d . -f1)

	if [[ "$first_octect" -ge 1 && "$first_octect" -le 126 ]]; then
		echo "Class A"
	elif [[ "$first_octect" -ge 128 && "$first_octect" -le 191 ]]; then
		echo "Class B"
	elif [[ "$first_octect" -ge 192 && "$first_octect" -le 223 ]]; then
		echo "Class C"
	else
		echo "Reserved/Special"
	fi
}

# Retrieve DNS Server Settings
get_dns_server(){
	DNS_SERVERS=$(grep nameserver /etc/resolv.conf 2>/dev/null | awk '{print $2}' | tr '\n' ' ')
	echo "Global DNS Servers: ${DNS_SERVERS:-N/A (Check /etc/resolv.conf)}"

}

# Retrieve Public IP Address
get_public_ip(){
	local PUBLIC_IP=$(curl -s --max-time 5 $PUBLIC_IP_SERVICE)

	if [ $? -eq 0 ] && [ ! -z "$PUBLIC_IP" ]; then
		echo "Public IP Address:  ${PUBLIC_IP}"
	else
		log_error "Failed to retrieve public IP (requires 'curl' and internet Access)."
		echo "N/A"
	fi
}

echo "============================================================="
echo "                    NETWORK INFORMATION REPORT"
echo -e "=============================================================\n"

echo "## Local Network Interfaces (NICs)"
echo "-----------------------------------------"
# List all NICs - Use 'ip -o a' for concise output
ip -o a | while read -r line; do
	INTERFACE=$(echo "$line" | awk '{print $2}')
	FAMILY=$(echo "$line" | awk '{print $3}')
	IP_CIDR=$(echo "$line" | awk '{print $4}')

	if [[ "$FAMILY" == "inet" && "$INTERFACE" != "lo" ]]; then
		IP_ADDRESS=$(echo "$IP_CIDR" | cut -d/ -f1)
		CIDR_PREFIX=$(echo "$IP_CIDR" | cut -d/ -f2)

		IP_CLASS=$(get_ip_class "$IP_ADDRESS")

		echo "Interface: **$INTERFACE**"
		echo "Local IP Address   : $IP_ADDRESS"
		echo "Subnet CIDR/Prefix : /$CIDR_PREFIX"
		echo "Network Range      : $IP_CIDR"
		echo "IP Class           : $IP_CLASS"
		echo ""
	fi
done
echo -e "-----------------------------------------\n"

echo "## Global Network Information"
echo "-----------------------------------------"
get_public_ip
get_dns_server
echo "-----------------------------------------"

echo -e "\n\n============================================================="
echo "INFO - Network information gathering complete."

exit 0
