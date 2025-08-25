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
        # Try common cached image IDs first
        local cache_key="${OPERATING_SYSTEM}_${OS_VERSION}_${OCI_SHAPE}"
        case "$cache_key" in
            "Oracle Linux_9_VM.Standard.A1.Flex")
                # Common Oracle Linux 9 ARM image ID - update as needed
                image_id="${OCI_CACHED_OL9_ARM_IMAGE:-}"
                if [[ -n "$image_id" ]]; then
                    log_info "Using cached Oracle Linux 9 ARM image ID"
                fi
                ;;
            "Oracle Linux_9_VM.Standard.E2.1.Micro")
                # Common Oracle Linux 9 AMD image ID - update as needed
                image_id="${OCI_CACHED_OL9_AMD_IMAGE:-}"
                if [[ -n "$image_id" ]]; then
                    log_info "Using cached Oracle Linux 9 AMD image ID"
                fi
                ;;
        esac
        
        # Fallback to API lookup if no cached image
        if [[ -z "$image_id" ]]; then
            log_info "Looking up latest image for OS $OPERATING_SYSTEM $OS_VERSION..."
            
            image_id=$(oci_cmd compute image list \
                --compartment-id "$comp_id" \
                --shape "$OCI_SHAPE" \
                --operating-system "$OPERATING_SYSTEM" \
                --operating-system-version "$OS_VERSION" \
                --limit 1 \
                --sort-by TIMECREATED \
                --sort-order DESC \
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
        --limit 1 \
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
    local ad_name="${3:-$OCI_AD}"  # Allow override for multi-AD cycling
    
    local launch_args=(
        "compute" "instance" "launch"
        "--availability-domain" "$ad_name"
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
    
    # Add availability configuration for auto-recovery
    local recovery_action="${RECOVERY_ACTION:-RESTORE_INSTANCE}"
    launch_args+=(
        "--availability-config"
        "{\"recoveryAction\": \"$recovery_action\"}"
    )
    
    # Add instance options for IMDS compatibility
    local legacy_imds="${LEGACY_IMDS_ENDPOINTS:-false}"
    launch_args+=(
        "--instance-options"
        "{\"areLegacyImdsEndpointsDisabled\": $legacy_imds}"
    )
    
    # Add configurable boot volume size
    local boot_volume_size="${BOOT_VOLUME_SIZE:-50}"
    if [[ "$boot_volume_size" -lt 50 ]]; then
        boot_volume_size=50  # Ensure minimum 50GB
        log_warning "Boot volume size increased to minimum 50GB"
    fi
    launch_args+=(
        "--boot-volume-size-in-gbs" "$boot_volume_size"
    )
    
    printf '%s\n' "${launch_args[@]}"
}

launch_instance() {
    local comp_id="$1"
    local image_id="$2"
    
    # Parse availability domains (support comma-separated list)
    local ad_list
    IFS=',' read -ra ad_list <<< "$OCI_AD"
    
    # Try each AD until success or all ADs exhausted
    local ad_index=0
    local max_attempts=${#ad_list[@]}
    local wait_time="${RETRY_WAIT_TIME:-30}"
    
    while [[ $ad_index -lt $max_attempts ]]; do
        local current_ad="${ad_list[$ad_index]}"
        log_info "Attempting to launch instance '$INSTANCE_DISPLAY_NAME' in AD $current_ad (attempt $((ad_index + 1))/$max_attempts)..."
        
        # Build launch command for current AD
        local launch_args
        readarray -t launch_args < <(build_launch_command "$comp_id" "$image_id" "$current_ad")
        
        # Execute launch command with single attempt for rate limiting
        local output
        local status
        
        set +e
        # Use oci_cmd to get debug output when enabled
        output=$(oci_cmd "${launch_args[@]}")
        status=$?
        set -e
        
        echo "$output"
        
        if [[ $status -eq 0 ]]; then
            # Success! Extract instance OCID
            local instance_id
            instance_id=$(echo "$output" | grep -o 'ocid1\.instance[^"]*' | head -1)
            
            if [[ -z "$instance_id" ]]; then
                log_error "Could not extract instance OCID from output"
                return 1
            fi
            
            log_success "Instance launched successfully in AD $current_ad! OCID: $instance_id"
            send_telegram_notification "success" "OCI instance created in $current_ad: ${INSTANCE_DISPLAY_NAME} (OCID: ${instance_id})"
            
            return 0
        fi
        
        # Handle launch errors
        local error_type
        error_type=$(handle_launch_error_with_ad "$output" "$current_ad" $((ad_index + 1)) $max_attempts)
        
        case "$error_type" in
            "CAPACITY"|"RATE_LIMIT")
                # Try next AD if available
                if [[ $((ad_index + 1)) -lt $max_attempts ]]; then
                    log_info "Trying next availability domain..."
                    ((ad_index++))
                    continue
                else
                    log_info "All ADs exhausted - will retry on next schedule"
                    return 0  # Not a failure, just capacity issue across all ADs
                fi
                ;;
            "LIMIT_EXCEEDED")
                # Special case: check if instance was created despite error
                log_info "LimitExceeded error - checking if instance was created anyway..."
                if verify_instance_creation "$comp_id" 3; then
                    return 0  # Instance was created successfully
                fi
                
                # Try next AD if available
                if [[ $((ad_index + 1)) -lt $max_attempts ]]; then
                    log_info "Trying next availability domain after LimitExceeded..."
                    ((ad_index++))
                    continue
                else
                    log_info "All ADs exhausted after LimitExceeded errors"
                    return 0
                fi
                ;;
            "SUCCESS"|"DUPLICATE")
                return 0  # Not a failure
                ;;
            *)
                # Real error - propagate failure
                return 1
                ;;
        esac
        
        # Add delay between AD attempts if configured
        if [[ $wait_time -gt 0 && $((ad_index + 1)) -lt $max_attempts ]]; then
            log_info "Waiting ${wait_time}s before trying next AD..."
            sleep "$wait_time"
        fi
        
        ((ad_index++))
    done
    
    # Should not reach here, but handle gracefully
    log_info "All availability domains attempted - will retry on next schedule"
    return 0
}

handle_launch_error_with_ad() {
    local error_output="$1"
    local current_ad="$2"
    local attempt="$3"
    local max_attempts="$4"
    local error_type
    
    error_type=$(get_error_type "$error_output")
    
    case "$error_type" in
        "CAPACITY")
            log_info "No capacity available for shape in AD $current_ad (attempt $attempt/$max_attempts)"
            echo "CAPACITY"
            return 0
            ;;
        "RATE_LIMIT")
            log_info "Rate limit detected in AD $current_ad (attempt $attempt/$max_attempts)"
            echo "RATE_LIMIT"
            return 0
            ;;
        "LIMIT_EXCEEDED")
            log_info "LimitExceeded error in AD $current_ad (attempt $attempt/$max_attempts)"
            echo "LIMIT_EXCEEDED"
            return 0
            ;;
        "DUPLICATE")
            log_info "Instance with this name already exists. Skipping creation."
            send_telegram_notification "info" "OCI instance already exists: ${INSTANCE_DISPLAY_NAME}"
            echo "DUPLICATE"
            return 0
            ;;
        "AUTH")
            log_error "Authentication/authorization error in AD $current_ad"
            send_telegram_notification "error" "OCI authentication error: Check credentials and permissions"
            echo "AUTH"
            return 0
            ;;
        "CONFIG")
            log_error "Configuration error detected in AD $current_ad"
            local error_line
            error_line=$(echo "$error_output" | head -1)
            send_telegram_notification "error" "OCI configuration error: ${error_line}"
            echo "CONFIG"
            return 0
            ;;
        "NETWORK")
            log_error "Network error detected in AD $current_ad"
            send_telegram_notification "error" "OCI network error: Check connectivity and network configuration"
            echo "NETWORK"
            return 0
            ;;
        *)
            log_error "Unexpected error during instance launch in AD $current_ad"
            local error_line
            error_line=$(echo "$error_output" | head -1)
            send_telegram_notification "error" "OCI instance launch failed in $current_ad: ${error_line}"
            echo "UNKNOWN"
            return 0
            ;;
    esac
}

verify_instance_creation() {
    local comp_id="$1"
    local max_checks="${2:-3}"
    local check_delay="${3:-20}"
    
    log_info "Verifying instance creation with $max_checks checks..."
    
    for ((i=1; i<=max_checks; i++)); do
        log_info "Instance verification check $i/$max_checks..."
        
        local instance_id
        instance_id=$(oci_cmd compute instance list \
            --compartment-id "$comp_id" \
            --display-name "$INSTANCE_DISPLAY_NAME" \
            --lifecycle-state "RUNNING,PROVISIONING" \
            --limit 1 \
            --query 'data[0].id' \
            --raw-output 2>/dev/null || echo "")
        
        if [[ -n "$instance_id" && "$instance_id" != "null" ]]; then
            local state
            state=$(oci_cmd compute instance get \
                --instance-id "$instance_id" \
                --query 'data."lifecycle-state"' \
                --raw-output 2>/dev/null || echo "")
            
            log_success "Instance found: $instance_id (state: $state)"
            send_telegram_notification "success" "OCI instance verified: ${INSTANCE_DISPLAY_NAME} (OCID: ${instance_id}, State: ${state})"
            return 0
        fi
        
        if [[ $i -lt $max_checks ]]; then
            log_info "Instance not found yet, waiting ${check_delay}s before next check..."
            sleep "$check_delay"
        fi
    done
    
    log_warning "Instance verification failed after $max_checks checks"
    return 1
}

# Main function
launch_oci_instance() {
    start_timer "total_execution"
    log_info "Starting OCI instance launch process..."
    
    # Check OCI CLI availability
    start_timer "oci_cli_check"
    check_oci_cli
    log_elapsed "oci_cli_check"
    
    # Determine compartment to use
    start_timer "compartment_setup"
    local comp_id
    comp_id=$(determine_compartment)
    log_elapsed "compartment_setup"
    
    # Check for existing instance (if enabled)
    if [[ "${CHECK_EXISTING_INSTANCE:-false}" == "true" ]]; then
        start_timer "existing_instance_check"
        local instance_status
        instance_status=$(check_existing_instance "$comp_id")
        log_elapsed "existing_instance_check"
        
        if [[ "$instance_status" == "EXISTS" ]]; then
            log_info "Skipping creation - instance already exists"
            log_elapsed "total_execution"
            return 0
        fi
    else
        log_info "Skipping existing instance check - attempting direct launch"
    fi
    
    # Lookup or use provided image ID
    start_timer "image_lookup"
    local image_id
    image_id=$(lookup_image_id "$comp_id")
    log_elapsed "image_lookup"
    
    # Launch the instance
    start_timer "instance_launch"
    launch_instance "$comp_id" "$image_id"
    log_elapsed "instance_launch"
    
    log_elapsed "total_execution"
}

# Run launch if called directly
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
    launch_oci_instance
fi