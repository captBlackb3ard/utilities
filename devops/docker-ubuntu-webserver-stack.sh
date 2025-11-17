#!/usr/bin/env bash

: "
 Bash script to install Docker (if needed), build an Ubuntu image with OpenSSH, Apache, vsftpd, & supervisord and run it with Docker compose.
 Tested on Linux Mint/Ubuntu Desktop.
 
 version = 0.8
 https://www.blackbeardcyber.com

 ** Use at your own risk
 
 How to Use This Script
 ===========================================================
 + This script assumes that the Linux host OS (Linux Mint/Ubuntu) has an active internet connection.
 + Script includes basic logging to assist with troubleshooting.

 + Download script and change execute permissions:
  chmod +x docker-ubuntu-webserver-stack.sh
 + Execute script with 'sudo':
  sudo ./docker-ubuntu-webserver-stack.sh

 + During execution, a project folder 'docker-ubuntu-server-web-stack' is created, and all additional
   config files are placed in this directory.
 + Once execution is completed, you can delete the folder with:
  sudo rm -rf docker-ubuntu-server-web-stack/

 + To logging via SSH/FTP, make sure to specify the port - 2222/2121, respectively, e.g.:
  ssh -p 2222 webstackuser@<container_ip>
"

set -e # Exit immediately if command exits with non-zero status
set -u # Treat unset variables as an error & exit
# Support non-Bash environments
(set -o pipefail) 2>/dev/null && set -o pipefail

# VTY Colour Variables
#-----------------------------------------------------
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # Reset VTY color

# CONFIG VARIABLES
#-----------------------------------------------------
PROJECT_DIR="${PWD}/docker-ubuntu-server-web-stack"
IMAGE_NAME="ubuntu-server-web-stack"
CONTAINER_NAME="ubuntu-server-web-stack"
SSH_USER="webstackuser"
# If SSH_PASSWORD is not set, a strong random password will be generated
SSH_PASSWORD="${SSH_PASSWORD:-}"

SSH_PORT=2222
HTTP_PORT=8080
FTP_PORT=2121
FTP_PASSIVE_START=21100
FTP_PASSIVE_END=21110
USER=$USER  # Current User Executing the Script


# Logging Config
#-----------------------------------------------------
LOG_FILE="$(pwd)/docker-ubuntu-webserver-stack-$(date +%F_%H-%M-%S).log"

# Send all stdout/err to console and log file
exec > >(tee -a "$LOG_FILE") 2>&1

# Trap any unhandled error
trap 'echo -e "${RED}[FATAL] An unexpected error occurred at line ${LINENO}. See log: ${LOG_FILE}${NC}" >&2' ERR

# Helpers
#-----------------------------------------------------
need_cmd() { command -v "$1" >/dev/null 2>&1; }

error_exit(){
  local msg="$1"
  local code=${2:-1}
  echo "${RED}ERROR${NC}:${msg}" >&2
  exit "$code"
}


#-----------------------------------------------------
echo 
echo "**********************************************************"
echo -e "              ${BLUE}Docker Ubuntu Server Web Stack${NC}"
echo "**********************************************************"
echo 

echo -e "**${RED}IMPORTANT${NC}:** Ensure host OS is up to date and critical data backed up before executing this script!"
echo
read -p "Do you want to proceed - No or Yes? (n/N/y/Y): " response
[ -z "$response" ] && response="N" #Set default response

#Check Response output
case "$response" in
	[yY] ) echo "Script will proceed with execution."
         echo
		;;
	[nN] ) echo "User '${USER}' opted to terminate script execution."
         echo
		exit 0  # Successful execution
		;;
	* 	) echo "'${response}' is an incorrect option. Execution aborted!" >&2
        echo
		exit 1
		;;
esac

echo "Logging to: ${LOG_FILE}"
echo 

## STEP 1 ---------------------------------------------------------------------------------
# Confirm Docker Engine & Compose are installed
echo -e "${BLUE}[1/7]${NC} Confirming Docker Engine, Compose, Plugins & Dependencies Installed..."


if ! need_cmd docker; then
  echo -e "${GREEN}[INFO]${NC}: Docker Engine not found. Installing Docker Engine..."
  if ! need_cmd sudo && [ "$EUID" -ne 0 ]; then
    error_exit "Sudo is required to install Docker. Please execute this script as root or use 'sudo'."
  fi

	apt update -y
	apt install ca-certificates curl  >&2
  install -m 0755 -d /etc/apt/keyrings  >&2
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc  >&2
  chmod a+r /etc/apt/keyrings/docker.asc  >&2
  # Add the repository to Apt sources:
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list  >&2
  apt update -y  >&2
  apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
	usermod -aG docker "$SUDO_USER" # Run Docker without 'sudo'

	echo -e "${GREEN}[INFO]${NC}: Step 1 completed - Docker installed!"
else
  # Docker installed - start Docker Engine
  echo -e "${GREEN}[INFO]${NC}: Docker Engine already installed."
fi

# Confirm Docker Engine Service is Running
if ! systemctl is-active --quiet docker; then
	echo -e "${GREEN}[INFO]${NC}: Startign Docker Engine..."
  systemctl start docker || error_exit "Failed to start Docker Engine."
fi 

if systemctl is-active --quiet docker; then
  echo -e "${GREEN}[INFO]${NC}: Docker Engine service is running. Proceeding to the next step."
else
  error_exit "Unable to start Docker Engine service. Script execution aborted."
fi 

# Confirm Docker Compose installed
if need_cmd docker compose &> /dev/null; then
	echo -e "${GREEN}[INFO]${NC}: Docker Compose (plugin) is installed. Proceeding to next step."
  echo
elif need_cmd docker-compose &> /dev/null; then
	echo -e "${GREEN}[INFO]${NC}: Docker Compose (standalone) is installed. Proceeding to next step."
  echo
else
  error_exit "Docker Compose is not installed. Script execution aborted."
  echo
fi 


## STEP 2 ---------------------------------------------------------------------------------
echo -e "${BLUE}[2/7]${NC} Creating Docker file..."

# Check if project directory exists
if [ ! -d PROJECT_DIR ]; then
	# Directory does not exist - create directory
	mkdir -p "${PROJECT_DIR}" || error_exit "Failed to create project directory ${PROJECT_DIR}"
fi

cd "${PROJECT_DIR}" || error_exit "Failed to change directory to: ${PROJECT_DIR}"

echo -e "${GREEN}[INFO]${NC}: Project Directory Created: ${PROJECT_DIR}"

# Create Dockerfile (Assume file does not exist)

cat > Dockerfile <<EOF
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && apt upgrade -y && \
  apt install -y --no-install-recommends  \
  openssh-server \
  apache2 \
  vsftpd \
  supervisor \
  curl ca-certificates \
  nano \
  vim \
  && rm -rf /var/lib/apt/lists/*

# Prep SSH
RUN mkdir -p /var/run/sshd /home/.sshseed && chmod 0755 /var/run/sshd
# Create a default user; password set at run time via chpasswd
ARG SSH_USER=webstackuser
RUN useradd -m -s /bin/bash "${SSH_USER}" && \
    mkdir -p /home/${SSH_USER} &&  \
    chown -R ${SSH_USER}:${SSH_USER} /home/${SSH_USER}

# Minimal SSH hardening
RUN sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config && \
 sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config && \
 sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config && \
 sed -i 's/^#\?UsePAM.*/UsePAM yes/' /etc/ssh/sshd_config && \
 echo 'ClientAliveInterval 300' >> /etc/ssh/sshd_config && \
 echo 'ClientAliveCountMax 2' >> /etc/ssh/sshd_config

# Apache index.html
COPY index.html /var/www/html/index.html
RUN chown -R www-data:www-data /var/www/html

# vsftpd Config
RUN mv /etc/vsftpd.conf /etc/vsftpd.conf.orig
COPY vsftpd.conf /etc/vsftpd.conf

# Supervisord Config
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Expose ports (SSH, HTTP, FTP control, FTP passive range)
EXPOSE 22 80 21 21100-21110

# Volumes for persistence
VOLUME ["/var/www/html", "/home"]

CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
EOF

DOCKFILE_NAME="Dockerfile"

#Confirm Docker File created
if [ ! -f DOCKFILE_NAME ]; then
	echo -e "${GREEN}[INFO]${NC}: Dockerfile created: (${PWD}/${DOCKFILE_NAME}).\n"
  echo
else
	error_exit "Error creating Dockerfile. Script execution aborted.\n"
  echo
fi


## STEP 3 ---------------------------------------------------------------------------------
echo -e "${BLUE}[3/7]${NC} Creating vsftpd and supervisord configs..." 

# Create VSFTPD config file
cat > vsftpd.conf <<EOF
# VSFTPD run in standalone mode (listening for incoming connections on defined port)
listen=YES
# Disable anonymous login
anonymous_enable=NO
# Permit local users to log into the FTP server
local_enable=YES
# Enable WRITE permissions (Upload, Edit, Delete)
write_enable=YES
# Users shown message if directory contains specified file
dirmessage_enable=YES
# Files use server local time configs
use_localtime=YES
# Activate logging of file uploads + downloads
xferlog_enable=YES
# Force active-mode data connections to originate from port 20
connect_from_port_20=YES
# Config FTP server welcome banner
ftpd_banner=Welcome to VSFTPD.
# Local users logged in are placed in 'chroot', preventing access to their home dir 
chroot_local_user=YES
# Prevent chroot directory from being writeable by the user
allow_writeable_chroot=YES

# Passive FTP Ports - Used for data transfer (match Docker port mapping)
pasv_enable=YES
pasv_min_port=21100
pasv_max_port=21110

# Reduce info leakage
hide_ids=YES

EOF

VSFTPD_FILE="vsftpd.config"
#Confirm VSFTPD Config File created
if [ ! -f VSFTPD_FILE ]; then
	echo -e "${GREEN}[INFO]${NC}: VSFTPD Configuration file created: (${PWD}/${VSFTPD_FILE})."
else
	error_exit "Error creating VSFTPD config file. Script execution aborted."
fi

# Generate index.html file
cat > index.html <<EOF
<html><h1>It Works!</h1><p>Docker Ubuntu Server Image/Container with SSH + Apache + vsftpd.</p></html>
EOF

HTML_FILE="index.html"
#Confirm index.html File created
if [ ! -f HTML_FILE ]; then
  echo -e "${GREEN}[INFO]${NC}: Apache index.html file created: (${PWD}/${HTML_FILE})."
  echo
else
  error_exit "Error creating Apache index.html file. Script execution aborted." 
  echo
fi


# Create supervisord.conf file
cat > supervisord.conf <<EOF
[supervisord]
nodaemon=true
logfile=/var/log/supervisord.log
pidfile=/var/run/supervisord.pid

[program:sshd]
command=/usr/sbin/sshd -D
autorestart=true
priority=10

[program:apache2]
command=/usr/sbin/apachectl -D FOREGROUND
autorestart=true
priority=20

[program:vsftpd]
command=/usr/sbin/vsftpd /etc/vsftpd.conf
autorestart=true
priority=30
EOF

SUPERVISORD_FILE="supervisord.conf"
#Confirm SUPERVISORD Config File created
if [ ! -f SUPERVISORD_FILE ]; then
	echo -e "${GREEN}[INFO]${NC}: SUPERVISORD Configuration file created: (${PWD}/${SUPERVISORD_FILE})."
  echo
else
	error_exit "Error creating SUPERVISORD config file. Script execution aborted." 
  echo
fi



## STEP 4 ---------------------------------------------------------------------------------
echo -e "${BLUE}[4/7]${NC} Creating Docker compose.yml file..."

cat > compose.yml <<EOF
services:
  stack:
    container_name: ${CONTAINER_NAME}
    build:
      context: .
      args:
        - SSH_USER=${SSH_USER}
    image: ${IMAGE_NAME}
    ports:
      - "${SSH_PORT}:22"
      - "${HTTP_PORT}:80"
      - "${FTP_PORT}:21"
      - "${FTP_PASSIVE_START}-${FTP_PASSIVE_END}:21100-21110"
    restart: unless-stopped
    volumes:
      - ./webroot:/var/www/html
      - ./home:/home
    environment:
      - SSH_USER=${SSH_USER}
    
EOF

COMPOSE_FILE="compose.yml"
#Confirm SUPERVISORD Config File created
if [ ! -f COMPOSE_FILE ]; then
	echo -e "${GREEN}[INFO]${NC}: Docker Compose file created: (${PWD}/${COMPOSE_FILE})."
  echo
else
	error_exit "Error creating Docker Compose file. Script execution aborted."
  echo
fi

# Ensure bind directories exist
mkdir -p webroot home


## STEP 5 ---------------------------------------------------------------------------------
echo -e "${BLUE}[5/7]${NC} Handling SSH Credentials..."

# Generate a strong random password if not provided via SSH_PASSWORD
if [ -z "$SSH_PASSWORD" ]; then
  if need_cmd openssl; then
    SSH_PASSWORD="$(openssl rand -base64 24 | tr -d '\n' | cut -c1-24)"
  else
    echo -e "${RED}[WARN]${NC}: openssl not found, using /dev/urandom for password generation."
    SSH_PASSWORD="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)"
  fi
fi

echo -e "${GREEN}[INFO]${NC}: Generated password for ${SSH_USER}: ${SSH_PASSWORD}"


## STEP 6 ---------------------------------------------------------------------------------
echo 
echo -e "${BLUE}[6/7]${NC} Building image & starting the web stack..."
docker compose build
docker compose up -d

# Ensure SSH password authentication is enabled inside the container & set password
echo ">> Enabling SSH password authentication inside the container and setting password..."
docker exec -u 0 "${CONTAINER_NAME}" bash -lc "sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || true"
docker exec -u 0 "${CONTAINER_NAME}" bash -lc "service ssh --full-restart || /etc/init.d/restart || pkill -HUP sshd || true"

# Set the user's password inside the container 
printf '%s:%s\n' "${SSH_USER}" "${SSH_PASSWORD}" | \
  docker exec -i -u 0 "${CONTAINER_NAME}" bash -lc 'chpasswd'

# Ensure ownership on mounted home directory
docker exec -u 0 "${CONTAINER_NAME}" bash -lc "chown -R ${SSH_USER}:${SSH_USER} /home/${SSH_USER} || true"

## STEP 7 ---------------------------------------------------------------------------------
if docker ps --filter "name=${CONTAINER_NAME}" --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}"; then
  echo 
  echo -e "${BLUE}[7/7]${NC} Docker Ubuntu Server Web Stack Setup Completed!"
  echo -e "${BLUE}**IMPORTANT**${NC}: Note copy and save the following details"

  echo "=========================================="
  echo "Container name: ${CONTAINER_NAME}"
  echo "Image: ${IMAGE_NAME}"
  echo "SSH user: ${SSH_USER}"
  echo "SSH password: ${SSH_PASSWORD}"
  echo "Host ports -> Container ports:"
  echo "  SSH   ${SSH_PORT} -> 22"
  echo "  HTTP  ${HTTP_PORT} -> 80"
  echo "  FTP   ${FTP_PORT} -> 21"
  echo "  FTP passive ${FTP_PASSIVE_START}-${FTP_PASSIVE_END} -> 21100-21110"
  echo "Web root: ${PROJECT_DIR}/webroot"
  echo "Home dir: ${PROJECT_DIR}/home/${SSH_USER}"
  echo "Try:  ssh -p ${SSH_PORT} ${SSH_USER}@localhost"
  echo "HTTP:  http://localhost:${HTTP_PORT}/"
  echo "FTP:   ftp -p localhost ${FTP_PORT}"
  echo "=========================================="
  echo -e "**${BLUE}NOTE${NC}:** For Docker group permissions to take effect, log out and then back in or execute 'newgrp docker' without sudo."
  echo
  exit 0
else
  error_exit "Docker Ubuntu Server Web Stack Setup did complete successfully. Container '${CONTAINER_NAME}'' is not running"
fi
