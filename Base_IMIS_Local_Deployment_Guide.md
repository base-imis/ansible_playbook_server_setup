# Base IMIS Local Deployment Guide

Step-by-step deployment, verification, and local browser access guide.

This guide describes how to deploy Base IMIS on the same server where Ansible is running. It covers requirements, local inventory, playbook order, verification, SSH access, Nginx Proxy Manager access, and GeoServer access through an SSH tunnel.

## 1. Basic Requirements

The web application and database are preferably deployed on two separate servers with identical specifications. They can also run on the same server with minor modifications.

### 1.1 Server Requirements

| Requirement | Recommendation |
|---|---|
| Operating system | Ubuntu 22.04 LTS or newer. Automation also supports Debian 12 or newer. |
| Disk space | At least 100 GB initially, plus space for GIS data, media, backups, images, and logs. |
| RAM | At least 8 GB. More may be required for large GIS datasets or higher traffic. |
| CPU | At least 4 CPU cores. More may be required for larger workloads. |
| Network | At least 100 Mbps and approximately 500 GB to 1 TB monthly transfer, depending on traffic. |

### 1.2 Software Requirements

| Software | Requirement |
|---|---|
| Web server | Nginx is used by the deployment. Apache is possible with modifications. |
| PHP | PHP 8 or later. The current Laravel playbook defaults to PHP 8.2.35. |
| Database | PostgreSQL 14, 15, or 16. PostgreSQL 14 is the default. |
| Spatial database | PostGIS and postgis_topology. |
| Routing | pgRouting is enabled by the PostgreSQL playbook. |
| GeoServer | GeoServer 2.28.2 is the current playbook default. |
| Containers | Docker Engine and Docker Compose plugin. |

### 1.3 Windows Access Tools

When the deployment engineer connects from a Windows computer, install the following tools before starting:

| Tool | Purpose |
|---|---|
| PuTTYgen | Create or convert the SSH private and public key pair used for server access. |
| PuTTY | Open an SSH terminal to the server and run the setup commands and Ansible playbooks. |
| WinSCP | Connect to the server over SFTP to upload, download, and manage deployment files. |

Use the SSH public key created with PuTTYgen on the server. Keep the private key secure and never commit it to Git or upload it to the deployment repository.

#### Download Putty and puttygen

Open the supplied PuTTY and PuTTYgen download page:

   https://puttygen.com/download-putty#PuTTY_for_windows
   
The download page displays the **Alternative Binary Files for PuTTY Windows** list, choose the 64-bit x86 files for most modern Windows computers:

| File | Download | Purpose |
|---|---|---|
| `putty.exe` | 64-bit x86 | PuTTY SSH terminal used to connect to the server and run commands. |
| `puttygen.exe` | 64-bit x86 | PuTTYgen key-generation tool used to create the Ed25519 SSH key. |

Scroll down the download page until the `puttygen.exe` section is visible. Download the 64-bit x86 `puttygen.exe` file as well as the 64-bit x86 `putty.exe` file.

For the complete process of installing and running PuTTY on Windows, use the same reference page:

https://puttygen.com/download-putty#PuTTY_for_windows


#### Create an Ed25519 SSH Key with PuTTYgen



The supplied page is a third-party download/reference page. Before running the installer or standalone executable, verify that the download is the expected PuTTY release and scan it with the organization's security tools. The official PuTTY release page remains the preferred source when available.

2. Download `puttygen.exe` if you are using the standalone PuTTYgen download, or download the PuTTY Windows installer if PuTTYgen is included in the package.
3. Open **PuTTYgen** from the Windows Start menu or run `puttygen.exe`.
4. Under **Parameters**, select **Ed25519**.
5. Click **Generate** and move the mouse over the blank area until key generation completes.
6. Enter a strong **Key passphrase(optional)** and confirm it.
7. Click **Save private key** and save the file in a secure location, for example:

   ```text
   C:\Users\YOUR_USERNAME\.ssh\base-imis-ed25519.ppk
   ```

8. In the **Public key for pasting into OpenSSH authorized_keys file** box, select and copy the complete public key text. Copy it as one line beginning with `ssh-ed25519`.
9. Keep the `.ppk` private key on the desktop computer only. Never paste the private key into the server, Git, WinSCP, or the deployment repository.



#### Connect with PuTTY

Use the same supplied download page as the reference for the PuTTY Windows package:

https://puttygen.com/download-putty#PuTTY_for_windows

1. Download the PuTTY Windows installer. Use the 64-bit installer for most modern Windows computers; use the 32-bit installer if required by the computer.
2. Run the installer with Windows administrator permissions.
3. Accept the welcome screen and keep the default installation directory unless there is a specific reason to change it.
4. Keep the standard PuTTY features selected. Add a desktop shortcut if it will be used frequently.
5. Complete the installation and click **Finish**.

#### Install and Configure WinSCP

1. Download WinSCP from the official website:

   https://winscp.net/eng/downloads.php

2. Run the installer.
3. Accept the license agreement.
4. Select the recommended installation type and complete the installation.
5. Open WinSCP and select **New Site**.
6. Configure the site as follows:

   | WinSCP setting | Value |
   |---|---|
   | File protocol | SFTP |
   | Host name | Server IP address |
   | Port number | Current SSH port, initially the provider port or `2224` after hardening |
   | User name | `root` initially, or `innovative` after SSH hardening |
   | Password | The password for the selected user, if password login is enabled |

#### Open PuTTY from WinSCP

After the WinSCP session is connected:

1. Open the **Commands** menu.
2. Select **Open in PuTTY**, or press `Ctrl+P`.
3. WinSCP opens PuTTY using the saved server connection settings.
4. Use the PuTTY terminal to run commands and playbooks. Use WinSCP for file transfer and file management.

WinSCP uses SFTP over SSH. Therefore, the SSH username, port, password, key, and firewall access must be correct before WinSCP can connect.

### 1.4 Deployment Engineer Requirements

- Linux server administration with Ubuntu or Debian.
- Docker and Docker Compose.
- Networking and port configuration.
- Firewall rules.
- PostgreSQL and PostGIS.
- GeoServer.
- Shell scripting.
- PHP and Laravel.
- NPM, Git, JavaScript, jQuery, and OpenLayers.

## 2. Script Based Deployment Requirements

These requirements are taken from the current setup scripts and Ansible playbooks. General operating-system, hardware, and software requirements are described in Section 1; the items below record the additional checks and inputs enforced by the automation.

### 2.1 Control Server

The general operating-system and software requirements are listed in Sections 1.1 and 1.2. The control-node setup script additionally checks or requires:

- `apt-get` and `dpkg` available.
- At least 1 GB free space on `/` for control-node setup.
- A valid deployment repository URL and permission to clone it.
- An SSH key when the target is a separate remote server. This is not required for the local `ansible_connection=local` setup.

Install the control-node tools:

~~~bash
sudo ./01-setup-control-node-safe.sh
~~~

### 2.2 Target Server

The Docker playbook validates the target operating system as Ubuntu 22.04 or newer, or Debian 12 or newer. It also expects Python 3, root or sudo access, a working package manager, systemd, and internet access for Docker installation and package downloads. For a local deployment, the target can be `localhost` using `ansible_connection=local`.

### 2.3 Recommended Capacity

The scripts do not enforce fixed hardware limits, but the complete deployment should have:

- At least 4 CPU cores.
- At least 8 GB RAM.
- At least 100 GB disk space, plus application and backup storage.
- Enough resources for GeoServer's default 2 GB memory limit, 1536 MB JVM heap, and 2 CPU cores.

### 2.4 SSH and Firewall Inputs

Prepare:

- An existing SSH session or recovery console during SSH hardening.
- Current and target SSH ports.
- A non-root administrative username and password.
- Trusted office, administrator, and control-server IP addresses or CIDRs.
- A decision about allowing HTTP 80 and HTTPS 443.
- Decisions about locking root, removing root authorized keys, and locking unused users.
- Remote syslog details if required.

### 2.5 Required Services and Ports

| Service | Port | Requirement or usage |
|---|---:|---|
| SSH | 2224 | Configured administrative SSH port in the current setup. |
| HTTP | 80 | Public web traffic. |
| HTTPS | 443 | Secure public web traffic. |
| Nginx Proxy Manager admin | 81 | Normally bound to localhost and accessed through an SSH tunnel. |
| PostgreSQL host | 15432 | Default host port, normally bound to localhost for local-only access. |
| GeoServer host | 18082 | Current host port, mapped to container port 8080. |
| Docker networks | N/A | PostgreSQL, GeoServer, Nginx, and Laravel must use matching network names. |

### 2.6 Docker

- Docker Engine installed and running.
- Docker Compose plugin available through 'docker compose'.
- Permission to use Docker.
- Enough disk space for images, volumes, databases, dependencies, and logs.

### 2.7 PostgreSQL

- PostgreSQL 14.
- A valid installation directory.
- Database name and administrator username.
- Database administrator and PostgreSQL superuser passwords.
- Host bind IP and port.
- Public and private allowlists if remote access is enabled.
- Matching PostgreSQL Docker network, 'postgres14_backend' by default for PostgreSQL 14.
- PostGIS, postgis_topology, and pgRouting are enabled.

### 2.8 GeoServer

- Docker and Docker Compose working.
- PostgreSQL deployed and its Docker network available.
- GeoServer version, container name, installation directory, and host port.
- GeoServer administrator credentials.
- Enough memory and CPU for the configured JVM.
- A4 and A3 background PDFs when printing backgrounds are enabled.
- Required extensions such as AuthKey, CSS, printing, and querylayer.

### 2.9 Nginx and Laravel

- Docker, Docker Compose, and Nginx Proxy Manager running.
- Reachable Laravel Git repository and branch.
- Project name, web folder, domain, and base path.
- Docker template repository and branch.
- Database details when database integration is enabled.
- GeoServer domain, workspace, and optional AuthKey secret when enabled.
- PHP version, application environment, debug setting, and additional environment variables.

## 3. Run the Initial Control Node Setup

The initial setup script is stored in the `ansible-playbook-server-setup` folder of the GitHub repository.

GitHub repository:

https://github.com/base-imis/ansible_playbook_server_setup

Initial control-node script:

https://github.com/base-imis/ansible_playbook_server_setup/01-setup-control-node-safe.sh

The script installs the control-node tools and then clones the Ansible playbook repository. A separate bootstrap directory is not required. Create the script directly in the current home directory:

~~~bash
sudo nano 01-setup-control-node-safe.sh
~~~

Open the GitHub file at `ansible-playbook-server-setup/01-setup-control-node-safe.sh`, copy only its raw script content, and paste it into the local file `/root/01-setup-control-node-safe.sh` opened in nano. Do not copy the Markdown code fences or the filename itself. Save with `Ctrl+O`, press `Enter`, and exit with `Ctrl+X`.

Make the file executable and check its syntax:

~~~bash
sudo chmod +x 01-setup-control-node-safe.sh
sudo bash -n 01-setup-control-node-safe.sh
~~~

No output from `bash -n` means the syntax check passed. Run the script:

~~~bash
sudo ./01-setup-control-node-safe.sh
~~~

When the script asks for the deployment repository URL, use:

~~~text
https://github.com/base-imis/ansible_playbook_server_setup.git
~~~

When it asks for the repository directory, use the default or choose:

~~~text
/root/server-setup-ansible
~~~

The script creates the repository directory, installs Ansible, Python, Git, the OpenSSH client, and sudo, then clones the repository. After it finishes, enter the cloned Ansible directory:

~~~bash
cd /root/server-setup-ansible
~~~

## 4. Run the Initial SSH Script


After `01-setup-control-node-safe.sh` completes, the Ansible repository has already been cloned and contains the existing `02-ssh.sh` file. Do not create or copy `02-ssh.sh` again. Enter the cloned repository and run the existing file:

~~~bash
cd /root/server-setup-ansible
sudo chmod +x 02-ssh.sh
sudo ./02-ssh.sh
~~~

This script prepares the root SSH directory and public-key files on the control server. It does not connect to or modify a separate managed server.

### What `02-ssh.sh` does

The script performs the following actions on the control server:

1. Creates or preserves `/root/.ssh` with secure permissions.
2. Creates or preserves `/root/.ssh/authorized_keys`.
3. Creates a dedicated Ed25519 Ansible key pair if one does not already exist:

   ```text
   /root/.ssh/id_ed25519_ansible
   /root/.ssh/id_ed25519_ansible.pub
   ```

4. Validates the private key, public key, and `authorized_keys` file.
5. Sets secure permissions on the SSH files.
6. Asks whether you want to add another public SSH key to `/root/.ssh/authorized_keys`.

When the script displays:

```text
Do you want to add a public SSH key to /root/.ssh/authorized_keys now? [y/N]:
```

Enter `y` if you want to use the Ed25519 public key created with PuTTYgen. The script then asks for the **public key or file path**:

- Paste the complete public key copied from PuTTYgen, beginning with `ssh-ed25519`; or
- Enter the path to a `.pub` file already on the server.

The script validates that the value is an OpenSSH public key, avoids adding an exact duplicate, and appends it to:

```text
/root/.ssh/authorized_keys
```

This public-key entry allows SSH key authentication for the root account while root login is permitted by the server's SSH configuration. The private key remains on the Windows computer and is selected in PuTTY or WinSCP.

Do not paste a private key into the prompt. A PuTTY private key normally has a `.ppk` extension and must never be placed in `authorized_keys`.

For a separate managed server, `02-ssh.sh` does not install the public key there. Use the provider console, an existing password-based SSH session, PuTTY, or WinSCP to add the public key to the managed user's `~/.ssh/authorized_keys` file. For the local deployment described in this guide, the control server and target are the same machine.

## 5. Configure the Local Inventory

~~~bash
cd ~/server-setup-ansible
nano inventory.ini
~~~

Use this inventory for a local deployment:

~~~ini
[control]
localhost ansible_connection=local

[managed]
server1 ansible_host=SERVER_IP ansible_user=INITIAL_SSH_USER ansible_port=22


[hardening_target:children]
control
~~~

Remove or comment out remote placeholders such as:

~~~ini
server1 ansible_host=SERVER_IP ansible_user=INITIAL_SSH_USER ansible_port=22
~~~

Test the inventory:

~~~bash
ansible-inventory --graph
ansible control -m ansible.builtin.ping
ansible managed -m ansible.builtin.ping
~~~

Expected result:

~~~text
localhost | SUCCESS
~~~

## 6. Deployment Order

~~~text
01 SSH hardening
02 Docker
03 Nginx Proxy Manager
04 Fail2ban
05 PostgreSQL/PostGIS/pgRouting
06 GeoServer
07 Shared Nginx initial setup
08 Laravel application
Verification
~~~

### 6.1 SSH Hardening

~~~bash
ansible-playbook playbooks/01_linux_ssh_setup_harden.yml
~~~

Configures the administrative user, hardens SSH, changes the SSH port if selected, restricts root login, configures firewall rules, and enables system hardening. Keep a recovery console available.

### 6.2 Docker Setup

~~~bash
ansible-playbook playbooks/02_docker_setup_hardening.yml
docker --version
docker compose version
~~~

Installs and hardens Docker and verifies the Docker daemon.

### 6.3 Nginx Proxy Manager

~~~bash
ansible-playbook playbooks/03_Nginx_proxy.yml
~~~

Creates the Nginx Proxy Manager configuration and starts the container.

#### Step 1: Remove the Old SSH Host Key

Before creating the tunnel, open Windows Command Prompt and remove the old SSH host-key entry:

~~~cmd
ssh-keygen -R "[217.216.59.198]:2224"
~~~

This removes the outdated entry from:

~~~text
C:\Users\User\.ssh\known_hosts
~~~

Run this step when the server was reinstalled, its SSH host key changed, or PuTTY/OpenSSH reports a host-key mismatch. You will be asked to accept the new host key when connecting again.

Local admin tunnel:

~~~cmd
ssh -p 2224 -N -L 8181:127.0.0.1:81 <server_name>@<server_ip>
~~~

Open 'http://127.0.0.1:8181'. Keep the tunnel terminal open.

### 6.4 Fail2ban

~~~bash
ansible-playbook playbooks/04_install_fail2ban.yml
~~~

Installs Fail2ban, protects SSH, configures the SSH jail, and whitelists trusted administrator IP addresses.

### 6.5 PostgreSQL PostGIS and pgRouting

~~~bash
ansible-playbook playbooks/05_install_postgres_hardened.yml
~~~

Starts PostgreSQL, enables PostGIS, postgis_topology, and pgRouting, creates databases and users, configures pg_hba.conf, applies access restrictions, and verifies readiness. After PostgreSQL is ready, restore the application database backup into the created database before deploying the Laravel application.

Local admin tunnel:

~~~cmd
ssh -p 2224 -N -L 15432:127.0.0.1:15432 <server_name>@<server_ip>
~~~

Later database administration:

~~~bash
ansible-playbook playbooks/051_postgres_helper.yml
~~~



### 6.6 GeoServer

~~~bash
ansible-playbook playbooks/06_install_hardened_geoserver.yml
~~~

Starts GeoServer locally in Docker, connects it to PostgreSQL, installs extensions, applies resource limits, configures credentials, and verifies the endpoint.

Current mapping:

~~~text
Container: geoserver
Server:    127.0.0.1:18082
Container: 8080
NPM config: /home/innovative/geoserver/NPM_ADVANCED_CONFIG.conf
~~~


Local GeoServer tunnel:

~~~cmd

ssh -p 2224 -N -L 80:127.0.0.1:18082 <server_name>@<server_ip>
~~~

Open http://localhost/geoserver

### Get the GeoServer AuthKey

The deployment creates the AuthKey UUID for the service user `geoserver_service_user`. Read it on the server with:

~~~bash
sudo sed -n '/<user[^>]*name="geoserver_service_user"/,/<\/user>/p' \
  /home/innovative/geoserver/geoserver_data/security/usergroup/default/users.xml \
  | grep -oP '(?<=<property name="UUID">)[0-9a-fA-F-]{36}'
~~~

Use the returned UUID as the `authkey` URL parameter. Keep it secret and do not put it in source control, browser history, proxy logs, or application logs.

To locate the AuthKey user from the GeoServer web console:

1. Sign in at `http://localhost/geoserver` with the GeoServer administrator account.
2. Open **Security -> Users, Groups, and Roles**.
3. Open the **Users** tab and select `geoserver_service_user`.
4. The generated UUID/AuthKey is stored in the server file shown above; run the command above to read it.

The web console identifies the AuthKey user, while the generated UUID is read from `users.xml` on the server.

### Load the GeoServer workspace from the server

Run the workspace importer from the server. It creates a Python virtual environment, installs the required package, and starts the interactive workspace import process:

~~~bash
sudo apt update
    sudo apt install -y python3-pip python3.12-venv

cd /home/innovative/ansible_playbook_server_setup/files/geoserver_workspace/workspace_manifest_tool
chmod +x run_workspace_manifest_tool.sh
./run_workspace_manifest_tool.sh
~~~

Follow the prompts to select the workspace manifest and enter the destination GeoServer and PostgreSQL connection details. The target database, user, schema, and required PostGIS extensions must already exist before importing the workspace.

The workspace importer defaults the target GeoServer URL to `http://localhost/geoserver`. Keep this SSH tunnel running in another terminal while creating the workspace, layers, and styles:

~~~bash
ssh -p 2224 -N -L 80:127.0.0.1:18082 <admin_user>@<server_ip>
~~~

The tunnel must remain open for the importer to communicate with GeoServer.

Later CORS changes:

~~~bash
ansible-playbook playbooks/061_geoserver_cors_helper.yml
~~~

### 6.7 Shared Nginx Initial Setup

Return to the Ansible repository directory:

~~~bash
cd /home/innovative/ansible_playbook_server_setup
~~~

~~~bash
ansible-playbook playbooks/07_shared_nginx_register.yml
~~~

Creates the shared Docker networks, shared Nginx directories, shared configuration, and shared-nginx container. Run it before Laravel deployment.

### 6.8 Laravel Application

~~~bash
ansible-playbook playbooks/08_Laravel_webapp_deploy.yml
~~~

Clones the Laravel repository, creates application containers, writes the .env file, configures PostgreSQL and GeoServer integration, runs Composer and optional NPM setup, starts the application, creates the project Nginx configuration, and reloads shared Nginx.

Example project configuration:

~~~text
/home/innovative/shared-nginx/nginx/conf.d/myapp.conf
~~~

Check that the PostgreSQL, shared web, and GeoServer Docker networks exist:

~~~bash
sudo docker network ls
sudo docker network inspect postgres14_backend shared-web geoserver_proxy
~~~

## 7. Configure GeoServer in Nginx Proxy Manager

| Setting | Value |
|---|---|
| Scheme | 'http' |
| Forward Hostname | 'geo' |
| Forward Port | '8080' |

Use the internal Docker upstream 'geo:8080'. Do not use '127.0.0.1:18082' as the Nginx Proxy Manager upstream. Port 18082 is for direct verification and SSH tunneling.

## 8. GeoServer Login Redirect Troubleshooting

If GeoServer redirects to 'http://localhost/geoserver/j_spring_security_check', update the proxy base URL for local testing:

1. Open 'http://127.0.0.1:18083/geoserver'.
2. Go to Settings and then Global.
3. Set Proxy Base URL to 'http://127.0.0.1:18083/geoserver'.
4. Save the setting.
5. Restart GeoServer:

~~~bash
sudo docker restart geo
~~~

6. Use 'http://127.0.0.1:18083/geoserver' again.

## 9. Verification

~~~bash
ansible-playbook verify/01_linux_ssh_setup_harden_verify.yml
ansible-playbook verify/02_docker_setup_hardening_verify.yml
ansible-playbook verify/03_Nginx_proxy_verify.yml
ansible-playbook verify/04_install_fail2ban_verify.yml
ansible-playbook verify/05_install_postgres_hardened_v2_verify.yml
ansible-playbook verify/06_install_hardened_geoserver_verify.yml
ansible-playbook verify/07_Laravel_webapp_deploy_verify.yml
ansible-playbook verify/08_shared_nginx_register_verify.yml
~~~

These read-only checks verify SSH, Docker, Nginx Proxy Manager, Fail2ban, PostgreSQL, PostGIS, pgRouting, GeoServer, Laravel, shared Nginx, and PHP-FPM connectivity.

## 10. Useful Commands

~~~bash
ssh -p 2224 innovative@217.216.59.198
sudo docker ps --format "table {{.Names}}\t{{.Ports}}"
sudo docker logs geo --tail=50
sudo ss -lntp | grep 18082
curl -I http://127.0.0.1:18082/geoserver
~~~

## 11. Optional Complete Run

After testing the playbooks individually:

~~~bash
./run-all.sh
~~~

When asked whether the SSH connection requires a login password, answer 'n' for local execution. Running the individual commands is safer because each stage can be verified before the next stage begins.
## 12. Prompt Reference by Script
This section lists the interactive prompts used by the scripts and playbooks. A prompt may be skipped when its value is supplied through an Ansible variable file or vault. The default shown is the default in the current script.

### 12.1 `01-setup-control-node-safe.sh`

| Prompt | What it asks for | Default or note |
|---|---|---|
| Upgrade all currently installed packages now? | Whether the control server should run a full package upgrade before installing the tools. | `y` or `N`; `N` skips the upgrade. |
| Deployment repository URL | The Git repository to clone after installing the control-node tools. | The script default may be overridden with the repository used by this deployment. |
| Repository directory | Where the cloned Ansible repository should be stored. | Usually `/root/server-setup-ansible` for a root login. |

### 12.2 `02-ssh.sh`

| Prompt | What it asks for | Default or note |
|---|---|---|
| Do you want to add a public SSH key to `/root/.ssh/authorized_keys` now? | Whether to add a PuTTYgen or other OpenSSH public key to the control server. | `y` or `N`. Enter `y` when adding the desktop public key. |
| Public key or file path | The complete public key line beginning with `ssh-ed25519`, or the path to a `.pub` file. | Private keys are rejected. |
| Add another public SSH key? | Whether to add another public key. | `y` or `N`. |

### 12.3 `01_linux_ssh_setup_harden.yml`

| Prompt from the playbook | What it asks for | Default or note |
|---|---|---|
| Enter the absolute path to the INITIAL SSH private key | Private key used to verify the new administrative user's SSH login. | Remote execution only; local execution skips it. |
| Enter the NEW non-root administrative Linux username | Username to create or use for administration. | Do not enter `root`. |
| Enter the password for the NEW administrative user | Password for the new user's sudo access. | Required unless supplied through variables. |
| Enter a NEW password for the root account | New root password, or blank to keep the current root password. | Separate from the administrative-user password. |
| Enter the CURRENT SSH port used to access this server | Current SSH port before hardening. | Enter the real current port; local mode displays its script hint. |
| Enter the NEW SSH port for the server after hardening | Port to use after SSH hardening. | Must be 1-65535; keep the current port if blank. |
| Enter the office public IPv4 address or CIDR | Office address allowed to connect through SSH. | Blank if not required. |
| Enter the Ansible control-server public IPv4 address or CIDR | Control-server address allowed through SSH. | Blank if not required. |
| Allow inbound HTTP port 80? | Whether the firewall allows public HTTP. | Default `yes`. |
| Allow inbound HTTPS port 443? | Whether the firewall allows public HTTPS. | Default `yes`. |
| Lock the root account? | Whether to lock root after administrative access is verified. | Default `yes`. |
| Delete `/root/.ssh/authorized_keys`? | Whether to remove root's authorized keys after the new user key is verified. | Default `yes`; do not choose this until recovery access is confirmed. |
| Lock other interactive Linux users? | Whether to lock unused users with UID 1000 or higher. | Default `no`. |
| Send system logs to a remote syslog server? | Whether to configure remote system logging. | Default `no`. |
| Enter the remote syslog server as HOST:PORT | Remote syslog destination when remote logging is enabled. | Example: `siem-server.com:514`. |
| Pause for confirmation before SSH and root-lock changes? | Whether to stop for a safety confirmation before applying high-risk changes. | Default `yes`; recommended for the first run. |

### 12.4 `02_docker_setup_hardening.yml`

| Prompt | What it asks for | Default |
|---|---|---|
| Install Docker audit rules? | Whether to install audit rules for Docker activity. | `yes` |
| Restart Docker automatically when its configuration changes? | Whether Ansible may restart Docker after configuration changes. | `yes` |
| Pause after each major section for manual testing? | Whether to stop between Docker setup stages. | `yes` |
| Maximum size of each Docker JSON log file | Maximum size of one container log file. | `50m` |
| Maximum number of Docker JSON log files | Number of rotated log files to retain. | `5` |

### 12.5 `03_Nginx_proxy.yml`

| Prompt | What it asks for | Default |
|---|---|---|
| Nginx Proxy Manager install directory | Directory for the Nginx Proxy Manager files. | `/home/innovative/nginx-proxy-manager` |
| SSH port used for the local admin tunnel | SSH port used when creating the Nginx Proxy Manager tunnel. | `2224` |
| SSH username shown in tunnel instructions | Username shown in the generated access instructions. | `innovative` |
| Stop/remove the existing NPM container and rebuild the directory? | Whether to delete and rebuild an existing installation. | `no` |
| Manage DOCKER-USER rules for NPM ports? | Whether to manage Docker firewall rules for ports 80, 81, and 443. | `yes` |
| Install lightweight NPM audit rules? | Whether to install audit rules for Nginx Proxy Manager. | `yes` |

### 12.6 `04_install_fail2ban.yml`

| Prompt | What it asks for | Default |
|---|---|---|
| SSH port to protect | SSH port that Fail2ban should monitor. | Blank detects it from `sshd`. |
| Admin/public IP or CIDR to whitelist | Main administrator address that must not be banned. | Required input. |
| Additional trusted IPs/CIDRs separated by spaces | Other addresses that should never be banned. | Optional. |
| Ban duration | How long a failed-login address remains banned. | `1h` |
| Failure counting window | Time window in which failures are counted. | `10m` |
| Maximum failed attempts | Number of failures before an address is banned. | `5` |
| Pause for final SSH verification? | Whether to wait for confirmation that SSH still works. | `yes` |

### 12.7 `05_install_postgres_hardened.yml`

| Prompt | What it asks for | Default |
|---|---|---|
| PostgreSQL major version | PostgreSQL version to deploy. | `14`; allowed values are 14, 15, and 16. |
| Install directory | Host directory for PostgreSQL files and data. | `/home/innovative/postgres14` |
| Default PostgreSQL database name | Database used for initial extension setup and administration. | `defaultdb` |
| DB admin user | Administrative PostgreSQL role. | `innovative` |
| Password for the DB admin user | Password for the administrative role. | Required and confirmed. |
| Password for the postgres superuser | Password for the PostgreSQL superuser. | Required and confirmed. |
| Host port for PostgreSQL | Port published on the server host. | `15432` |
| Host bind IP | Address where PostgreSQL is published. | `127.0.0.1` for local-only access; use `0.0.0.0` only when remote access is intended. |
| Access mode | Chooses public/admin allowlists only or public plus private/internal allowlists. | `A` or `C`; default `A`. |
| Public/admin allowed IPs or CIDRs | Comma-separated public or administrator addresses allowed to connect. | Optional. |
| Private/internal allowed IPs or CIDRs | Comma-separated private or internal addresses allowed to connect. | Optional. |
| Apply strict CONNECT isolation? | Restricts database users to explicitly allowed databases. | `true` |
| Disable postgres login after admin verification? | Disables the default `postgres` login after verification. | `true` |
| Pause before using an existing PostgreSQL data directory? | Stops before reusing existing data. | `yes` |

### 12.8 `051_postgres_helper.yml`

| Prompt | What it asks for | When used or default |
|---|---|---|
| What do you want to do? | Selects the operation: create user, change access, create/clone database, remove access, or disable login. | Enter 1, 2, 3, 4, or 5. |
| PostgreSQL Docker container name | Container to administer. | `postgres14` |
| Published PostgreSQL host port | Host port used for optional firewall rules. | Blank auto-detects it. |
| Full HOST path to `pg_hba.conf` | Host path to the PostgreSQL access-control file. | Blank auto-detects the Docker bind mount. |
| Privileged PostgreSQL admin user | Superuser or privileged role used for administration. | Inventory user or `innovative`. |
| Password for the privileged PostgreSQL admin user | Password for the privileged role. | Required and hidden. |
| Application DB username | User affected by operations 1, 2, 4, or 5. | Required for those operations. |
| Password for the application DB user | Password for a newly created application user. | Operation 1 only. |
| Give the new user access to an existing database now? | Whether a newly created user should receive access immediately. | Operation 1; default `yes`. |
| Application database name | Database to which access is applied. | Operations 1, 2, and 4 when applicable. |
| Choose access | Selects `readonly`, `readwrite`, or `fullaccess`. | Default `readwrite`. |
| Allowed client IPs/CIDRs | Networks or addresses allowed to connect as the selected DB user. | Required when granting access. |
| Manage DOCKER-USER firewall rules? | Whether to manage host firewall rules for the allowed clients. | Default `no`; usually no for same-host Docker networks. |
| New database name | Name of a new database. | Operation 3 only. |
| Source database to clone | Existing source database for cloning. | Operation 3; blank creates an empty database. |
| Administrative owner role for the new database | Role that owns the new database. | Operation 3; defaults to the admin user. |

### 12.9 `06_install_hardened_local_geoserver.yml`

| Prompt | What it asks for | Default |
|---|---|---|
| GeoServer install directory | Host directory for GeoServer data and build files. | `/home/innovative/geoserver` |
| Create the default printing `config.yml` if it does not exist? | Whether to create the MapFish Print configuration. | `yes` |
| Full path to the A4 printing background template PDF | A4 background PDF used by printing. | Required when requested. |
| Full path to the A3 printing background template PDF | A3 background PDF used by printing. | Required when requested. |
| GeoServer version | GeoServer version to deploy. | `2.28.2` |
| Container name | Docker container name. | `geo` |
| Docker image name | Existing image name, or blank to build `custom-geoserver:<version>`. | Blank uses the generated custom image. |
| Localhost host port for GeoServer | Host port mapped to container port 8080. | `18082` |
| Nginx Proxy Manager container name | NPM container used for network integration. | `nginx-proxy-manager` |
| Primary GeoServer workspace | Main workspace for the deployment. | Optional. |
| GeoServer layer for authenticated WMS/WFS tests | Layer in `workspace:layer` format for tests. | Optional. |
| Skip GeoServer demo data on a new data directory? | Whether to omit demo data. | `yes` |
| Install stable extensions at container startup? | Whether to install the selected extensions. | `yes` |
| Stable extensions, comma-separated | Extensions such as AuthKey, CSS, printing, and querylayer. | `authkey,css,printing,querylayer` |
| Remove `gt-complex*.jar` libraries from the image? | Whether to remove those libraries. | `no` |
| Unprivileged GeoServer UID | Runtime user ID. | `1002` |
| Unprivileged GeoServer GID | Runtime group ID. | `1002` |
| Set GeoServer administrator credentials from the container environment? | Whether to set admin credentials during this run. | `yes` |
| GeoServer administrator username | GeoServer admin login name. | `admin` |
| GeoServer administrator password | GeoServer admin login password. | Required and confirmed. |
| Automate GeoServer WMS/WFS/AuthKey security setup now? | Whether to create the service security configuration. | Default security setup value, normally `yes`. |
| GeoServer OGC service username | Service account for OGC security tests or access. | `geoserver_service_user` |
| Password for the GeoServer OGC service user | Password for the OGC service account. | Optional or required when security setup is enabled. |
| GeoServer OGC service role | Role assigned to the OGC service account. | `ROLE_GEOSERVER_SERVICE` |
| Docker network used by PostgreSQL | PostgreSQL network GeoServer must join. | `postgres14_backend` |
| Container memory limit | Maximum GeoServer container memory. | `2g` |
| Container memory reservation | Reserved GeoServer memory. | `512m` |
| JVM heap maximum | Maximum Java heap. | `1536m` |
| Container CPU limit | Maximum CPU allocation. | `2.0` |
| Back up an existing GeoServer data directory? | Whether to back up data before deployment. | `yes` |
| Pause at the local Nginx checkpoint? | Whether to pause before Nginx-related steps. | `yes` |

### 12.10 `061_geoserver_cors_helper.yml`

| Prompt | What it asks for | Default or note |
|---|---|---|
| GeoServer container name | Container whose CORS configuration will be changed. | The helper default is `geoserver`; use the actual name, `geo`, in the current setup. |
| Full host path to `geoserver-web.xml` | Host path to the mounted web.xml file. | Blank auto-detects the Docker mount. |
| CORS origins to add, comma-separated | Origins allowed by GeoServer CORS. | Required. |
| When using `*`, type `allow wildcard` | Explicit confirmation for allowing every origin. | Required only when using `*`. |
| Apply the CORS update and restart GeoServer? | Whether to write the change and restart the container. | `yes` |

### 12.11 `07_shared_nginx_register.yml`

This playbook has no `vars_prompt` block. Its values are defined in the playbook, including the shared base path, shared Nginx directory, shared Nginx container name, Nginx Proxy Manager container name, and the `shared-web` and `npm-network` Docker networks. It creates the shared Nginx foundation before Laravel deployment.

### 12.12 `08_Laravel_webapp_deploy.yml`

| Prompt | What it asks for | Default |
|---|---|---|
| Project name | Name used for the application directory and containers. | `myapp` |
| Laravel project repo URL | HTTPS URL of the Laravel Git repository. | Required. |
| Web app folder name | Folder name inside the project. | Blank derives it from project and repository names. |
| Git branch | Branch to clone. | `main` |
| Domain/subdomain | Domain used by shared Nginx. | `app.local` |
| Use database? | Whether to configure PostgreSQL integration. | `n` |
| Use GeoServer? | Whether to configure GeoServer integration. | `n` |
| Configure the PII encryption feature? | Whether to run PII setup. | `n` |
| Is the database completely empty? | Whether the deployment should treat the database as empty. | `n` |
| Run npm setup? | Whether to install/build frontend dependencies. | `y` |
| Base path | Parent directory for the project. | `/home/innovative` |
| Docker template repository | Repository used to create the Docker project. | `https://github.com/imis-base-docker.git` |
| Docker template Git branch | Template repository branch. | `main` |
| Proceed if the project directory already exists? | Whether to continue when the target directory exists. | `n` |
| Database type | Local or remote database mode. | `local` |
| PostgreSQL network name | Docker network used for PostgreSQL. | `postgres14_backend` |
| Shared web Docker network name | Network shared with Nginx. | `shared-web` |
| Verify Laravel-owned clickjacking headers? | Whether to perform the header check. | `yes` |
| Optional public URL for final clickjacking verification | Public URL used for that check. | Blank skips it. |
| PHP major.minor.patch version | PHP version used by PHP, Artisan, and Composer containers. | `8.2.35` |
| PostgreSQL container name or database host | Database host or Docker container name. | `postgres14` |
| Database port | PostgreSQL port inside the selected connection mode. | `5432` |
| Database name | Application database name. | Blank uses the project name. |
| Database username | Application database user. | `app` |
| Database user password | Password for the application DB user. | Blank when DB is disabled; otherwise required and confirmed. |
| GeoServer workspace name | Workspace used by the application. | `workspace` |
| GeoServer AuthKey secret | AuthKey value used by the application. | Optional. |
| Google API key | Google Maps or related API key. | Optional. |
| App name | Application display name. | `Laravel` |
| App environment | Application environment. | `production` |
| App debug | Whether debug mode is enabled. | `false` |
| Additional environment entries | Extra values in `KEY=value;KEY2=value2` format. | Blank. |
| `SEED_SUPER_ADMIN_NAME` | Name for the optional seeded administrator. | Blank. |
| `SEED_SUPER_ADMIN_USERNAME` | Username for the optional seeded administrator. | Blank. |
| `SEED_SUPER_ADMIN_EMAIL` | Email for the optional seeded administrator. | Blank. |
| `SEED_SUPER_ADMIN_PASSWORD` | Password for the optional seeded administrator. | Blank and confirmed when supplied. |

### 12.13 Verification Playbooks

The verification playbooks are read-only and do not ask for interactive input. They use the inventory and the values already present on the server to check the corresponding deployment stage.
