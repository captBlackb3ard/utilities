import socket
import netifaces
import requests
import logging
import sys
import ipaddress
import platform
import re
import os


"""
Script Usage
-----------------------------------------------------------
# Execute the following commands at a Linux terminal:
- python -m venv network_env
- source ./network_env/bin/activate
- pip3 install -r network_requirements.txt

# After the required Python modules are installed, execute the following:
- python3 network.py

# NOTE: 
+ All logging and error information stored in the 'network_info.log' file within the same directory as this script
+ Ideally this script does not need to run as root or adminstrator.
"""


# Basic logging to file & console
logging.basicConfig(
	level=logging.INFO,
	format='%(asctime)s - %(levelname)s - %(message)s',
	handlers=[
		logging.FileHandler("network_info.log"),
		logging.StreamHandler(sys.stdout)
	]
)

# Helpers
def get_ip_class(ip_address: str) -> str:
	# Determines the IP class (A, B, or C) based on teh first octet
	first_octet = int(ip_address.split('.')[0])
	try:
		if 1 <= first_octet <= 126:
			return "Class A"
		elif 128 <= first_octet <= 191:
			return "Class B"
		elif 192 <= first_octet <= 223:
			return "Class C"
		else:
			return "Reserver/Special"
	except Exception as e:
		logging.warning(f"Could not determine the IP class: {e}")
		return "unknown"

# Retrieve DNS Server IP address
def get_dns_server() -> str:
	servers = []
	# Try reading /etc/resolv.conf file (Linux only)
	is_linux = platform.system() == "Linux" or os.path.exists("/proc")
	
	if is_linux:
		DNS_CONF_PATH = "/etc/resolv.conf"
		try:	
			with open(DNS_CONF_PATH, 'r') as f:
				for line in f:
					if line.strip().startswith("nameserver"):
						ip_match = re.search(r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}', line)
						if ip_match:
							servers.append(ip_match.group(0))
		except Exception as e:
			logging.warning(f"{DNS_CONF_PATH}not found. Cannot determine DNS servers.")
		except Exception as e:
			logging.error(f"Error reading {DNS_CONF_PATH}: {e}")
	else:
		logging.info ("Not Linux Operating System")
	# Fallback to netifaces if available
	if not servers:
		try:
			servers = netifaces.dns.get_nameservers()
		except AttributeError:
			logging.warning("netifaces.dns is not available.")
		except Exception as e:
			logging.error(f"General error using netifaces.dns: {e}")
		
	return ", ".join(servers) if servers else "N/A (Could not determine DNS server)"

# Retrieve Public IP Address
def get_public_ip() -> str:
	try:
		response = requests.get('https://api.ipify.org')
		response.raise_for_status() # Raise exception for bad status codes (4xx or 5xx)
		#results['Public Internet IP Address'] = response.text.strip()
		return response.text.strip()
	except Exception as e:
		logging.error(f"Error retrieving public IP address (requires internet connection) : {e}")
		#results['Public Internet IP Address'] = "ERROR (Internet Required)"
		return "ERROR (Internet Required)"

# Gather Main Network Information
def gather_network_info():
	nic_info_list = []

	# 1 - Gather NIC Details
	logging.info("Gathering all local network interface details...")
	try:
		interfaces = netifaces.interfaces()
		for nic in interfaces:
			address = netifaces.ifaddresses(nic)

			# Check IPv4 Address
			if netifaces.AF_INET in address:
				for ip_info in address[netifaces.AF_INET]:
					local_ip = ip_info.get('addr')
					sbnt_msk = ip_info.get('netmask')

					if local_ip and sbnt_msk:
						if local_ip.startswith('127'): # Skip loop-back 127.0.0.1
							continue
						try:
							# Calculate CIDR and Network Range
							network_cidr = str(ipaddress.ip_network(f'{local_ip}/{sbnt_msk}', strict=False))
							ip_class = get_ip_class(local_ip)

							nic_info_list.append({
									'Interface' : nic,
									'Local IP Address': local_ip,
									'Subnet Mask': sbnt_msk,
									'Network Range (CIDR)': network_cidr,
									'IP Class': ip_class
								})
						except Exception as e:
							logging.warning(f"Skipping '{nic}' due to IP address calculation error: {e}")
	except Exception as e:
		logging.error("Critical error gathering local network details: {e}")

	# 2 - DNS Server IP Address
	logging.info("Checking for DNS Server addresses ...")
	# netifaces.gateways() can be used, but for DNS, the netifaces.ifaddresses is sometimes incomplete
	# Reading (Linux/macOS) /etc/resolv.conf or (Windows) registry is more accurate but OS-dependent
	# Usign netifaces's built in DNS retrieval method (if available), else default to a common path

	# results['DNS Server IP Address'] = get_dns_server()
	dns_results = get_dns_server()

	# 3 - Public Internet IP Address
	logging.info("Retrieving public IP address from external service ...")
	# Use external service to determine public IP
	public_ip = get_public_ip()

	# Display Results
	print("\n" + "="*50)
	print(" NETWORK INFORMATION REPORT")
	print("="*50)

	# Display NIC Specific Info
	if nic_info_list:
		print("\n## Local Network Interfaces (NICs):")
		print("-"*35)
		for info in nic_info_list:
			print(f"**Interface:**      **{info['Interface']}**")
			print(f"Local IP Address:   {info['Local IP Address']}")
			print(f"Subnet Mask:        {info['Subnet Mask']}")
			print(f"Network Range/CIDR: {info['Network Range (CIDR)']}")
			print(f"IP Class:           {info['IP Class']}\n")
		print("-"*35)
	else:
		print("## No active IPv4 network interfaces found.")

	print("\n## Global Network Information")
	print("-"*35)
	print(f"Public Internet IP address: {public_ip}")
	print(f"DNS Server IP Address: {dns_results}")
	print("-"*35)

	print("\n" + "="*50)
	logging.info("Network information gathering complete.")

# 4 - Execute script
if __name__ == "__main__":
	try:
		gather_network_info()
	except Exception as e:
		logging.critical(f"Fatal error encountered during execution: {e}")
