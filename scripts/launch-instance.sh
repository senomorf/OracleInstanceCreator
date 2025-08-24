#!/bin/bash

# Launch OCI instance script
# Core logic for creating Oracle Cloud Infrastructure instances

set -euo pipefail

source "$(dirname "$0")/utils.sh"
source "$(dirname "$0")/notify.sh"

determine_compartment() {
    local comp_id
    
    if [[ -z "${OCI_COMPARTMENT_ID:-}" ]]; then
        comp_id="$OCI_TENANCY_OCID"
        log_info "Using tenancy OCID as compartment"
    else
        comp_id="$OCI_COMPARTMENT_ID"
        log_info "Using specified compartment"
    fi
    
    echo "$comp_id"
}

lookup_image_id() {
    local comp_id="$1"
    local image_id
    
    if [[ -n "${OCI_IMAGE_ID:-}" ]]; then
        image_id="$OCI_IMAGE_ID"
        log_info "Using specified image ID"
    else
        log_info "Looking up latest image for OS $OPERATING_SYSTEM $OS_VERSION..."
        
        image_id=$(oci_cmd compute image list \
            --compartment-id "$comp_id" \
            --all \
            --shape "$OCI_SHAPE" \
            --operating-system "$OPERATING_SYSTEM" \
            --operating-system-version "$OS_VERSION" \
            --query 'data[0].id' \
            --raw-output)
            
        if [[ -z "$image_id" || "$image_id" == "null" ]]; then
            local error_msg="No image found for $OPERATING_SYSTEM $OS_VERSION"
            log_error "$error_msg"
            send_telegram_notification "error" "OCI poller error: $error_msg"
            die "$error_msg"
        fi
        
        log_info "Found image ID: $image_id"
    fi
    
    echo "$image_id"
}

check_existing_instance() {
    local comp_id="$1"
    local existing_id
    
    log_info "Checking for existing instance: $INSTANCE_DISPLAY_NAME"
    
    existing_id=$(oci_cmd compute instance list \
        --compartment-id "$comp_id" \
        --display-name "$INSTANCE_DISPLAY_NAME" \
        --all \
        --query 'data[0].id' \
        --raw-output)
    
    if [[ -n "$existing_id" && "$existing_id" != "null" ]]; then
        log_info "Instance '$INSTANCE_DISPLAY_NAME' already exists (OCID: $existing_id)"
        echo "EXISTS"
        return 0
    fi
    
    echo "NOT_EXISTS"
}

build_launch_command() {
    local comp_id="$1"
    local image_id="$2"
    
    local launch_args=(
        "compute" "instance" "launch"
        "--availability-domain" "$OCI_AD"
        "--compartment-id" "$comp_id"
        "--shape" "$OCI_SHAPE"
        "--subnet-id" "$OCI_SUBNET_ID"
        "--image-id" "$image_id"
        "--display-name" "$INSTANCE_DISPLAY_NAME"
        "--assign-private-dns-record" "true"
        "--ssh-authorized-keys-file" "$HOME/.ssh/private_key_pub.pem"
    )
    
    # Add shape configuration for flexible shapes
    if [[ "$OCI_SHAPE" == *"Flex" ]]; then
        launch_args+=(
            "--shape-config" 
            "{\"ocpus\": ${OCI_OCPUS}, \"memoryInGBs\": ${OCI_MEMORY_IN_GBS}}"
        )
    fi
    
    # Set public IP assignment
    if [[ "$ASSIGN_PUBLIC_IP" == "true" ]]; then
        launch_args+=("--assign-public-ip" "true")
    else
        launch_args+=("--assign-public-ip" "false")
    fi
    
    printf '%s\n' "${launch_args[@]}"
}

launch_instance() {
    local comp_id="$1"
    local image_id="$2"
    
    log_info "Attempting to launch instance '$INSTANCE_DISPLAY_NAME' in AD $OCI_AD..."
    
    # Build launch command
    local launch_args
    readarray -t launch_args < <(build_launch_command "$comp_id" "$image_id")
    
    # Execute launch command with single attempt for rate limiting
    local output
    local status
    
    set +e
    # Use oci directly instead of oci_cmd to avoid any potential retry logic
    log_debug "Executing OCI command: ${launch_args[*]}"
    output=$(oci "${launch_args[@]}" 2>&1)
    status=$?
    set -e
    
    echo "$output"
    
    if [[ $status -ne 0 ]]; then
        # Check for rate limiting first to avoid further API calls
        if echo "$output" | grep -qi "too many requests\|rate limit\|throttle\|429"; then
            log_info "Rate limit detected - will retry on next schedule"
            log_info "Capacity issue detected - will retry on next schedule"
            return 0
        fi
        
        if handle_launch_error "$output"; then
            # Other capacity errors - log and exit successfully
            log_info "Capacity issue detected - will retry on next schedule"
            return 0
        else
            # Real error - propagate failure
            return 1
        fi
    fi
    
    # Extract instance OCID from successful output
    local instance_id
    instance_id=$(echo "$output" | grep -o 'ocid1\.instance[^"]*' | head -1)
    
    if [[ -z "$instance_id" ]]; then
        log_error "Could not extract instance OCID from output"
        return 1
    fi
    
    log_success "Instance launched successfully! OCID: $instance_id"
    send_telegram_notification "success" "OCI instance created: ${INSTANCE_DISPLAY_NAME} (OCID: ${instance_id})"
    
    return 0
}

handle_launch_error() {
    local error_output="$1"
    local error_type
    
    error_type=$(get_error_type "$error_output")
    
    case "$error_type" in
        "CAPACITY")
            log_info "No capacity available for shape at this time. Will retry on next schedule."
            return 0  # Not a failure, just capacity issue
            ;;
        "AUTH")
            log_error "Authentication/authorization error"
            send_telegram_notification "error" "OCI authentication error: Check credentials and permissions"
            return 1
            ;;
        "CONFIG")
            log_error "Configuration error detected"
            local error_line
            error_line=$(echo "$error_output" | head -1)
            send_telegram_notification "error" "OCI configuration error: ${error_line}"
            return 1
            ;;
        "NETWORK")
            log_error "Network error detected"
            send_telegram_notification "error" "OCI network error: Check connectivity and network configuration"
            return 1
            ;;
        *)
            log_error "Unexpected error during instance launch"
            local error_line
            error_line=$(echo "$error_output" | head -1)
            send_telegram_notification "error" "OCI instance launch failed: ${error_line}"
            return 1
            ;;
    esac
}

# Main function
launch_oci_instance() {
    log_info "Starting OCI instance launch process..."
    
    # Check OCI CLI availability
    check_oci_cli
    
    # Determine compartment to use
    local comp_id
    comp_id=$(determine_compartment)
    
    # Check for existing instance
    local instance_status
    instance_status=$(check_existing_instance "$comp_id")
    
    if [[ "$instance_status" == "EXISTS" ]]; then
        log_info "Skipping creation - instance already exists"
        return 0
    fi
    
    # Lookup or use provided image ID
    local image_id
    image_id=$(lookup_image_id "$comp_id")
    
    # Launch the instance
    launch_instance "$comp_id" "$image_id"
}

# Run launch if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    launch_oci_instance
fi