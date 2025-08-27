#!/bin/bash

# Setup SSH configuration
# This script configures SSH public key for instance access

set -euo pipefail

source "$(dirname "$0")/utils.sh"

setup_ssh_config() {
	log_info "Setting up SSH configuration..."

	# Validate required environment variable
	require_env_var "INSTANCE_SSH_PUBLIC_KEY"

	# Create SSH directory if it doesn't exist
	mkdir -p ~/.ssh

	# Create SSH public key file
	echo "${INSTANCE_SSH_PUBLIC_KEY}" >~/.ssh/private_key_pub.pem
	chmod 644 ~/.ssh/private_key_pub.pem

	log_success "SSH public key configured successfully"
}

# Run setup if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	setup_ssh_config
fi
