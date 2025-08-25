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
    log_info "Checking for proxy configuration..."
    
    if [[ -n "${OCI_PROXY_URL:-}" ]]; then
        log_info "OCI_PROXY_URL found - parsing proxy configuration"
        
        # Parse format: USER:PASS@HOST:PORT
        if [[ "$OCI_PROXY_URL" =~ ^([^:]+):([^@]+)@([^:]+):([0-9]+)$ ]]; then
            local proxy_user="${BASH_REMATCH[1]}"
            local proxy_pass="${BASH_REMATCH[2]}"
            local proxy_host="${BASH_REMATCH[3]}"
            local proxy_port="${BASH_REMATCH[4]}"
            
            # Construct proxy URL with authentication
            local proxy_url="http://${proxy_user}:${proxy_pass}@${proxy_host}:${proxy_port}/"
            
            # Set both uppercase and lowercase versions for maximum compatibility
            export HTTP_PROXY="${proxy_url}"
            export HTTPS_PROXY="${proxy_url}"
            export http_proxy="${proxy_url}"
            export https_proxy="${proxy_url}"
            
            log_debug "Proxy configured for ${proxy_host}:${proxy_port} with authentication (credentials not logged)"
            log_success "Proxy configuration applied successfully"
        else
            log_error "Invalid OCI_PROXY_URL format. Expected: USER:PASS@HOST:PORT"
            log_error "Example: myuser:mypass@proxy.example.com:3128"
            die "Proxy configuration failed - check OCI_PROXY_URL secret format"
        fi
    else
        log_info "No OCI_PROXY_URL found - OCI CLI will run without proxy"
    fi
}

# Run setup if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_oci_config
    setup_proxy_config
fi