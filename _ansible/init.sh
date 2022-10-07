#!/bin/bash

# Install pip and pywinrm
sudo pip3 install --upgrade pip
/usr/bin/python3.8 -m pip install --user --ignore-installed pywinrm

# Install neccessary ansible packages
ansible-galaxy collection install -vvvv ansible.windows
ansible-galaxy collection install -vvvv community.windows
ansible-galaxy collection install -vvvv chocolatey.chocolatey

# Test connection to the Windows machines
ansible -i hosts -m win_ping windows-servers
