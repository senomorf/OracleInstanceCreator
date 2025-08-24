#!/bin/bash

# Configuration validation script
# Validates all required environment variables and provides defaults

set -euo pipefail

source "$(dirname "$0")/utils.sh"

validate_oci_configuration() {
    log_info "Validating OCI configuration..."
    
    # Required OCI configuration
    require_env_var "OCI_USER_OCID"
    require_env_var "OCI_KEY_FINGERPRINT"
    require_env_var "OCI_TENANCY_OCID" 
    require_env_var "OCI_REGION"
    require_env_var "OCI_PRIVATE_KEY"
    require_env_var "OCI_SUBNET_ID"
    
    # Validate OCID formats
    if ! is_valid_ocid "$OCI_USER_OCID"; then
        die "Invalid OCI_USER_OCID format: $OCI_USER_OCID"
    fi
    
    if ! is_valid_ocid "$OCI_TENANCY_OCID"; then
        die "Invalid OCI_TENANCY_OCID format: $OCI_TENANCY_OCID"
    fi
    
    if ! is_valid_ocid "$OCI_SUBNET_ID"; then
        die "Invalid OCI_SUBNET_ID format: $OCI_SUBNET_ID"
    fi
    
    # Optional compartment ID (defaults to tenancy)
    if [[ -n "${OCI_COMPARTMENT_ID:-}" ]] && ! is_valid_ocid "$OCI_COMPARTMENT_ID"; then
        die "Invalid OCI_COMPARTMENT_ID format: $OCI_COMPARTMENT_ID"
    fi
    
    # Optional image ID validation
    if [[ -n "${OCI_IMAGE_ID:-}" ]] && ! is_valid_ocid "$OCI_IMAGE_ID"; then
        die "Invalid OCI_IMAGE_ID format: $OCI_IMAGE_ID"
    fi
    
    log_success "OCI configuration validation passed"
}

validate_instance_configuration() {
    log_info "Validating instance configuration..."
    
    # Required instance configuration with defaults
    export OCI_AD="${OCI_AD:-fgaj:AP-SINGAPORE-1-AD-1}"
    export OCI_SHAPE="${OCI_SHAPE:-VM.Standard.A1.Flex}"
    export INSTANCE_DISPLAY_NAME="${INSTANCE_DISPLAY_NAME:-oci-free-instance}"
    export OPERATING_SYSTEM="${OPERATING_SYSTEM:-Oracle Linux}"
    export OS_VERSION="${OS_VERSION:-9}"
    export ASSIGN_PUBLIC_IP="${ASSIGN_PUBLIC_IP:-false}"
    
    # Flexible shape configuration
    if [[ "$OCI_SHAPE" == *"Flex" ]]; then
        export OCI_OCPUS="${OCI_OCPUS:-4}"
        export OCI_MEMORY_IN_GBS="${OCI_MEMORY_IN_GBS:-24}"
        
        # Validate numeric values
        if ! [[ "$OCI_OCPUS" =~ ^[0-9]+$ ]] || [[ "$OCI_OCPUS" -le 0 ]]; then
            die "OCI_OCPUS must be a positive integer, got: $OCI_OCPUS"
        fi
        
        if ! [[ "$OCI_MEMORY_IN_GBS" =~ ^[0-9]+$ ]] || [[ "$OCI_MEMORY_IN_GBS" -le 0 ]]; then
            die "OCI_MEMORY_IN_GBS must be a positive integer, got: $OCI_MEMORY_IN_GBS"
        fi
        
        log_info "Flexible shape configuration: ${OCI_OCPUS} OCPUs, ${OCI_MEMORY_IN_GBS}GB RAM"
    fi
    
    # Validate boolean values
    if [[ "$ASSIGN_PUBLIC_IP" != "true" && "$ASSIGN_PUBLIC_IP" != "false" ]]; then
        die "ASSIGN_PUBLIC_IP must be 'true' or 'false', got: $ASSIGN_PUBLIC_IP"
    fi
    
    log_success "Instance configuration validation passed"
}

validate_ssh_configuration() {
    log_info "Validating SSH configuration..."
    
    require_env_var "INSTANCE_SSH_PUBLIC_KEY"
    
    # Basic SSH public key format validation
    if ! echo "$INSTANCE_SSH_PUBLIC_KEY" | grep -q "^ssh-"; then
        log_warning "SSH public key doesn't start with 'ssh-', this may cause issues"
    fi
    
    log_success "SSH configuration validation passed"
}

validate_notification_configuration() {
    log_info "Validating notification configuration..."
    
    require_env_var "TELEGRAM_TOKEN"
    require_env_var "TELEGRAM_USER_ID"
    
    # Basic Telegram token format validation (should be numeric:alphanumeric)
    if ! [[ "$TELEGRAM_TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
        log_warning "Telegram token format may be invalid"
    fi
    
    # Telegram user ID should be numeric
    if ! [[ "$TELEGRAM_USER_ID" =~ ^[0-9]+$ ]]; then
        die "TELEGRAM_USER_ID must be numeric, got: $TELEGRAM_USER_ID"
    fi
    
    log_success "Notification configuration validation passed"
}

print_configuration_summary() {
    log_info "Configuration Summary:"
    echo "  Region: $OCI_REGION"
    echo "  Availability Domain: $OCI_AD"
    echo "  Shape: $OCI_SHAPE"
    if [[ "$OCI_SHAPE" == *"Flex" ]]; then
        echo "  OCPUs: $OCI_OCPUS"
        echo "  Memory: ${OCI_MEMORY_IN_GBS}GB"
    fi
    echo "  Instance Name: $INSTANCE_DISPLAY_NAME"
    echo "  Operating System: $OPERATING_SYSTEM $OS_VERSION"
    echo "  Public IP: $ASSIGN_PUBLIC_IP"
    echo "  Compartment: ${OCI_COMPARTMENT_ID:-$OCI_TENANCY_OCID (tenancy)}"
}

# Main validation function
validate_all_configuration() {
    log_info "Starting configuration validation..."
    
    validate_oci_configuration
    validate_instance_configuration
    validate_ssh_configuration
    validate_notification_configuration
    
    print_configuration_summary
    
    log_success "All configuration validation completed successfully"
}

# Run validation if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    validate_all_configuration
fi