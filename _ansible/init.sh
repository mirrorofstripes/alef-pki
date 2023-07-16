#!/bin/bash

# Install pip and pywinrm
dnf install -y python3.11-pip
python3.11 -m pip install pywinrm requests

# Install neccessary ansible packages
ansible-galaxy collection install -vvvv ansible.windows
ansible-galaxy collection install -vvvv community.windows
ansible-galaxy collection install -vvvv microsoft.ad
ansible-galaxy collection install -vvvv chocolatey.chocolatey

# Test connection to all the machines
ansible -i /opt/alef-pki/_ansible/inventory/ -m ping linux-servers
ansible -i /opt/alef-pki/_ansible/inventory/ -m win_ping windows-servers
