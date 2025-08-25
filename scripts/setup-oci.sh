#!/bin/bash

# Setup OCI CLI configuration
# This script configures OCI CLI authentication using environment variables

set -euo pipefail

source "$(dirname "$0")/utils.sh"

setup_oci_config() {
    log_info "Setting up OCI configuration..."
    
    # Validate required environment variables
    require_env_var "OCI_USER_OCID"
    require_env_var "OCI_KEY_FINGERPRINT" 
    require_env_var "OCI_TENANCY_OCID"
    require_env_var "OCI_REGION"
    require_env_var "OCI_PRIVATE_KEY"
    
    # Create OCI config directory
    mkdir -p ~/.oci
    
    # Create OCI config file
    cat > ~/.oci/config <<EOL
[DEFAULT]
user=${OCI_USER_OCID}
fingerprint=${OCI_KEY_FINGERPRINT}
tenancy=${OCI_TENANCY_OCID}
region=${OCI_REGION}
key_file=${HOME}/.oci/oci_api_key.pem
EOL
    
    chmod 600 ~/.oci/config
    log_info "OCI config file created"
    
    # Create OCI private key file
    echo "${OCI_PRIVATE_KEY}" > ~/.oci/oci_api_key.pem
    chmod 600 ~/.oci/oci_api_key.pem
    log_info "OCI private key file created"
    
    log_success "OCI configuration completed successfully"
}

# Setup proxy configuration
setup_proxy_config() {
    log_info "Setting up proxy configuration..."
    parse_and_configure_proxy false
}

# Run setup if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_oci_config
    setup_proxy_config
fi