#!/bin/bash

# Oracle Instance Lifecycle Management Script
# Provides automated instance rotation and lifecycle management capabilities
# Building upon existing OCI automation for hands-off instance management

set -euo pipefail

# Source required dependencies
source "$(dirname "${BASH_SOURCE[0]:-$0}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]:-$0}")/notify.sh"

# Default configuration values
readonly DEFAULT_MIN_AGE_HOURS=24
readonly DEFAULT_ROTATION_STRATEGY="oldest_first"
readonly DEFAULT_HEALTH_CHECK_ENABLED=true
readonly DEFAULT_AUTO_ROTATE_INSTANCES=false
readonly DEFAULT_DRY_RUN=false

# Lifecycle management configuration
readonly LIFECYCLE_STATE_FILE="lifecycle-state.json"

# Initialize lifecycle management
init_lifecycle_manager() {
    log_info "Initializing instance lifecycle manager"
    
    # Validate required environment variables
    require_env_var "OCI_COMPARTMENT_ID"
    require_env_var "OCI_REGION"
    
    # Create lifecycle state file if it doesn't exist
    if [[ ! -f "$LIFECYCLE_STATE_FILE" ]]; then
        echo '{"instances": [], "last_rotation": null, "statistics": {"total_rotations": 0, "last_updated": null}}' > "$LIFECYCLE_STATE_FILE"
        log_debug "Created lifecycle state file: $LIFECYCLE_STATE_FILE"
    fi
    
    log_success "Lifecycle manager initialized successfully"
}

# Get lifecycle configuration from environment with defaults
get_lifecycle_config() {
    export AUTO_ROTATE_INSTANCES=${AUTO_ROTATE_INSTANCES:-$DEFAULT_AUTO_ROTATE_INSTANCES}
    export INSTANCE_MIN_AGE_HOURS=${INSTANCE_MIN_AGE_HOURS:-$DEFAULT_MIN_AGE_HOURS}
    export ROTATION_STRATEGY=${ROTATION_STRATEGY:-$DEFAULT_ROTATION_STRATEGY}
    export HEALTH_CHECK_ENABLED=${HEALTH_CHECK_ENABLED:-$DEFAULT_HEALTH_CHECK_ENABLED}
    export DRY_RUN=${DRY_RUN:-$DEFAULT_DRY_RUN}
    
    log_debug "Lifecycle configuration loaded:"
    log_debug "  AUTO_ROTATE_INSTANCES: $AUTO_ROTATE_INSTANCES"
    log_debug "  INSTANCE_MIN_AGE_HOURS: $INSTANCE_MIN_AGE_HOURS"
    log_debug "  ROTATION_STRATEGY: $ROTATION_STRATEGY"
    log_debug "  HEALTH_CHECK_ENABLED: $HEALTH_CHECK_ENABLED"
    log_debug "  DRY_RUN: $DRY_RUN"
}

# Get all instances in compartment with detailed information
get_instance_list() {
    local compartment_id="$1"
    local output
    
    log_debug "Retrieving instance list from compartment: $compartment_id"
    
    if ! output=$(oci_cmd compute instance list \
        --compartment-id "$compartment_id" \
        --lifecycle-state "RUNNING,PROVISIONING,STARTING,STOPPED,STOPPING" \
        --query 'data[*].{id: id, name: "display-name", state: "lifecycle-state", shape: shape, created: "time-created", region: region}' \
        --output json 2>/dev/null); then
        log_error "Failed to retrieve instance list from OCI"
        return 1
    fi
    
    echo "$output"
}

# Calculate instance age in hours
calculate_instance_age_hours() {
    local creation_time="$1"
    local current_time
    current_time=$(date +%s)
    
    # Convert OCI timestamp to epoch (handles both formats: with and without timezone)
    local creation_epoch
    if ! creation_epoch=$(date -d "$creation_time" +%s 2>/dev/null); then
        # Fallback for different date formats
        creation_epoch=$(date -d "${creation_time%.*}Z" +%s 2>/dev/null || echo 0)
    fi
    
    if [[ "$creation_epoch" -eq 0 ]]; then
        log_warning "Could not parse creation time: $creation_time"
        echo "0"
        return 1
    fi
    
    local age_seconds=$((current_time - creation_epoch))
    local age_hours=$((age_seconds / 3600))
    
    echo "$age_hours"
}

# Check instance health status
check_instance_health() {
    local instance_id="$1"
    local health_score=100
    local health_details=""
    
    log_debug "Checking health for instance: $instance_id"
    
    if [[ "$HEALTH_CHECK_ENABLED" != "true" ]]; then
        log_debug "Health check disabled - returning default healthy score"
        echo "$health_score"
        return 0
    fi
    
    # Get instance details
    local instance_info
    if ! instance_info=$(oci_cmd compute instance get \
        --instance-id "$instance_id" \
        --query 'data.{state: "lifecycle-state", fault_domain: "fault-domain", availability_domain: "availability-domain"}' \
        --output json 2>/dev/null); then
        log_warning "Failed to get instance details for health check: $instance_id"
        health_score=50
        health_details="API_UNAVAILABLE"
    else
        local state
        state=$(echo "$instance_info" | jq -r '.state // "unknown"' 2>/dev/null)
        
        case "$state" in
            "RUNNING")
                health_score=100
                health_details="RUNNING"
                ;;
            "STARTING"|"PROVISIONING")
                health_score=75
                health_details="TRANSITIONAL"
                ;;
            "STOPPED")
                health_score=25
                health_details="STOPPED"
                ;;
            "STOPPING"|"TERMINATING"|"TERMINATED")
                health_score=0
                health_details="TERMINATING"
                ;;
            *)
                health_score=50
                health_details="UNKNOWN_STATE"
                ;;
        esac
    fi
    
    log_debug "Instance $instance_id health: score=$health_score, details=$health_details"
    echo "$health_score"
}

# Get current shape utilization (E2: 2/2 instances, A1: 4/4 OCPUs)
get_shape_utilization() {
    local shape="$1"
    local compartment_id="$2"
    local current_count=0
    local max_count=0
    
    log_debug "Calculating utilization for shape: $shape"
    
    # Get current instances of this shape
    local instances
    if instances=$(oci_cmd compute instance list \
        --compartment-id "$compartment_id" \
        --lifecycle-state "RUNNING,PROVISIONING,STARTING" \
        --query "data[?shape=='$shape'].id" \
        --output json 2>/dev/null); then
        
        current_count=$(echo "$instances" | jq '. | length' 2>/dev/null || echo 0)
    fi
    
    # Determine maximum based on shape type
    case "$shape" in
        "VM.Standard.E2.1.Micro")
            max_count=2  # Free tier limit: 2 E2.1.Micro instances
            ;;
        "VM.Standard.A1.Flex")
            # For A1.Flex, count OCPUs instead of instances
            local total_ocpus=0
            if instances=$(oci_cmd compute instance list \
                --compartment-id "$compartment_id" \
                --lifecycle-state "RUNNING,PROVISIONING,STARTING" \
                --query "data[?shape=='$shape'].{id: id, ocpus: \"shape-config\".ocpus}" \
                --output json 2>/dev/null); then
                
                total_ocpus=$(echo "$instances" | jq '[.[].ocpus // 0] | add' 2>/dev/null || echo 0)
            fi
            current_count=$total_ocpus
            max_count=4  # Free tier limit: 4 A1 OCPUs total
            ;;
        *)
            log_warning "Unknown shape for utilization calculation: $shape"
            max_count=1
            ;;
    esac
    
    local utilization_percent=0
    if [[ $max_count -gt 0 ]]; then
        utilization_percent=$(( (current_count * 100) / max_count ))
    fi
    
    log_debug "Shape $shape utilization: $current_count/$max_count ($utilization_percent%)"
    echo "$utilization_percent"
}

# Check if shape is at capacity limit
is_shape_at_limit() {
    local shape="$1"
    local compartment_id="$2"
    local utilization
    
    utilization=$(get_shape_utilization "$shape" "$compartment_id")
    
    if [[ $utilization -ge 100 ]]; then
        log_debug "Shape $shape is at capacity limit (${utilization}%)"
        return 0
    else
        log_debug "Shape $shape has available capacity (${utilization}%)"
        return 1
    fi
}

# Select instances for rotation based on strategy
select_instances_for_rotation() {
    local shape="$1"
    local compartment_id="$2"
    local count="$3"
    local strategy="$4"
    
    log_info "Selecting $count instance(s) of shape $shape for rotation using strategy: $strategy"
    
    # Get all instances of the specified shape
    local instances
    if ! instances=$(oci_cmd compute instance list \
        --compartment-id "$compartment_id" \
        --lifecycle-state "RUNNING,PROVISIONING,STARTING,STOPPED" \
        --query "data[?shape=='$shape'].{id: id, name: \"display-name\", created: \"time-created\", state: \"lifecycle-state\"}" \
        --output json 2>/dev/null); then
        log_error "Failed to get instances for rotation selection"
        return 1
    fi
    
    local instance_count
    instance_count=$(echo "$instances" | jq '. | length' 2>/dev/null || echo 0)
    
    if [[ $instance_count -eq 0 ]]; then
        log_info "No instances found for shape: $shape"
        return 0
    fi
    
    log_debug "Found $instance_count instances of shape $shape"
    
    # Filter instances that meet minimum age requirement
    local eligible_instances="[]"
    local min_age_hours="$INSTANCE_MIN_AGE_HOURS"
    
    while IFS= read -r instance; do
        local instance_id created_time
        instance_id=$(echo "$instance" | jq -r '.id')
        created_time=$(echo "$instance" | jq -r '.created')
        
        local age_hours
        age_hours=$(calculate_instance_age_hours "$created_time")
        
        if [[ $age_hours -ge $min_age_hours ]]; then
            log_debug "Instance $instance_id is eligible (age: ${age_hours}h >= ${min_age_hours}h)"
            eligible_instances=$(echo "$eligible_instances" | jq --argjson inst "$instance" --arg age "$age_hours" '. + [($inst + {"age_hours": ($age | tonumber)})]')
        else
            log_debug "Instance $instance_id too young (age: ${age_hours}h < ${min_age_hours}h)"
        fi
    done < <(echo "$instances" | jq -c '.[]')
    
    local eligible_count
    eligible_count=$(echo "$eligible_instances" | jq '. | length')
    
    if [[ $eligible_count -eq 0 ]]; then
        log_info "No instances meet minimum age requirement (${min_age_hours}h)"
        return 0
    fi
    
    log_debug "Found $eligible_count eligible instances for rotation"
    
    # Apply rotation strategy
    local selected_instances
    case "$strategy" in
        "oldest_first")
            log_debug "Applying oldest_first strategy"
            selected_instances=$(echo "$eligible_instances" | jq --arg count "$count" 'sort_by(.age_hours) | reverse | .[:($count | tonumber)]')
            ;;
        "least_utilized")
            log_debug "Applying least_utilized strategy (with health scoring)"
            # For least_utilized, we need to check instance health/utilization
            local scored_instances="[]"
            while IFS= read -r instance; do
                local instance_id health_score
                instance_id=$(echo "$instance" | jq -r '.id')
                health_score=$(check_instance_health "$instance_id")
                
                scored_instances=$(echo "$scored_instances" | jq --argjson inst "$instance" --arg health "$health_score" '. + [($inst + {"health_score": ($health | tonumber)})]')
            done < <(echo "$eligible_instances" | jq -c '.[]')
            
            # Select instances with lowest health scores first
            selected_instances=$(echo "$scored_instances" | jq --arg count "$count" 'sort_by(.health_score) | .[:($count | tonumber)]')
            ;;
        *)
            log_error "Unknown rotation strategy: $strategy"
            return 1
            ;;
    esac
    
    local selected_count
    selected_count=$(echo "$selected_instances" | jq '. | length')
    
    if [[ $selected_count -gt 0 ]]; then
        log_info "Selected $selected_count instance(s) for rotation:"
        echo "$selected_instances" | jq -r '.[] | "  - \(.name) (\(.id)) - Age: \(.age_hours)h, State: \(.state)"'
        echo "$selected_instances"
    else
        log_info "No instances selected for rotation"
    fi
}

# Terminate instance with safety checks
terminate_instance() {
    local instance_id="$1"
    local instance_name="$2"
    local dry_run="$3"
    
    log_info "Preparing to terminate instance: $instance_name ($instance_id)"
    
    # Safety check: Verify instance exists and get current state
    local instance_info
    if ! instance_info=$(oci_cmd compute instance get \
        --instance-id "$instance_id" \
        --query 'data.{state: "lifecycle-state", name: "display-name"}' \
        --output json 2>/dev/null); then
        log_error "Failed to verify instance before termination: $instance_id"
        return 1
    fi
    
    local current_state
    current_state=$(echo "$instance_info" | jq -r '.state')
    
    # Safety check: Don't terminate already terminating instances
    if [[ "$current_state" == "TERMINATING" || "$current_state" == "TERMINATED" ]]; then
        log_warning "Instance $instance_name is already in state: $current_state"
        return 0
    fi
    
    # Dry run mode
    if [[ "$dry_run" == "true" ]]; then
        log_info "[DRY RUN] Would terminate instance: $instance_name ($instance_id)"
        log_info "[DRY RUN] Current state: $current_state"
        return 0
    fi
    
    # Send pre-termination notification
    if [[ "${ENABLE_NOTIFICATIONS:-}" == "true" ]]; then
        local message="Terminating Oracle Cloud instance for lifecycle management:
        
**Instance:** $instance_name
**OCID:** $instance_id
**Reason:** Automated lifecycle rotation
**Strategy:** $ROTATION_STRATEGY"
        
        send_telegram_notification "warning" "$message"
    fi
    
    log_info "Terminating instance: $instance_name ($instance_id)"
    
    # Perform termination
    local terminate_output
    if terminate_output=$(oci_cmd compute instance terminate \
        --instance-id "$instance_id" \
        --force 2>&1); then
        
        log_success "Successfully initiated termination for instance: $instance_name"
        
        # Update lifecycle statistics
        update_lifecycle_statistics "instance_terminated" "$instance_id" "$instance_name"
        
        # Send success notification
        if [[ "${ENABLE_NOTIFICATIONS:-}" == "true" ]]; then
            send_telegram_notification "success" "Instance $instance_name terminated successfully for lifecycle management"
        fi
        
        return 0
    else
        log_error "Failed to terminate instance $instance_name: $terminate_output"
        
        # Send error notification
        if [[ "${ENABLE_NOTIFICATIONS:-}" == "true" ]]; then
            send_telegram_notification "error" "Failed to terminate instance $instance_name: $terminate_output"
        fi
        
        return 1
    fi
}

# Update lifecycle statistics
update_lifecycle_statistics() {
    local action="$1"
    local instance_id="$2"
    local instance_name="$3"
    
    local timestamp
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')
    
    # Read current statistics
    local current_stats
    if [[ -f "$LIFECYCLE_STATE_FILE" ]]; then
        current_stats=$(cat "$LIFECYCLE_STATE_FILE")
    else
        current_stats='{"instances": [], "last_rotation": null, "statistics": {"total_rotations": 0, "last_updated": null}}'
    fi
    
    # Update statistics based on action
    case "$action" in
        "instance_terminated")
            current_stats=$(echo "$current_stats" | jq --arg ts "$timestamp" --arg id "$instance_id" --arg name "$instance_name" '
                .statistics.total_rotations += 1 |
                .statistics.last_updated = $ts |
                .last_rotation = $ts |
                .instances += [{"action": "terminated", "instance_id": $id, "instance_name": $name, "timestamp": $ts}]
            ')
            ;;
    esac
    
    # Write updated statistics
    echo "$current_stats" > "$LIFECYCLE_STATE_FILE"
    log_debug "Updated lifecycle statistics: $action for $instance_name"
}

# Perform instance rotation for a specific shape
rotate_instances_for_shape() {
    local shape="$1"
    local compartment_id="$2"
    local dry_run="${3:-$DRY_RUN}"
    
    log_info "Starting instance rotation for shape: $shape"
    
    # Check if shape is at capacity limit
    if ! is_shape_at_limit "$shape" "$compartment_id"; then
        log_info "Shape $shape is not at capacity limit - no rotation needed"
        return 0
    fi
    
    log_info "Shape $shape is at capacity limit - proceeding with rotation"
    
    # Determine how many instances to rotate (typically 1 for gradual rotation)
    local instances_to_rotate=1
    
    # Select instances for rotation
    local selected_instances
    if ! selected_instances=$(select_instances_for_rotation "$shape" "$compartment_id" "$instances_to_rotate" "$ROTATION_STRATEGY"); then
        log_error "Failed to select instances for rotation"
        return 1
    fi
    
    local selected_count
    selected_count=$(echo "$selected_instances" | jq '. | length' 2>/dev/null || echo 0)
    
    if [[ $selected_count -eq 0 ]]; then
        log_info "No instances selected for rotation"
        return 0
    fi
    
    # Terminate selected instances
    local termination_failures=0
    while IFS= read -r instance; do
        local instance_id instance_name
        instance_id=$(echo "$instance" | jq -r '.id')
        instance_name=$(echo "$instance" | jq -r '.name')
        
        if ! terminate_instance "$instance_id" "$instance_name" "$dry_run"; then
            log_error "Failed to terminate instance: $instance_name"
            ((termination_failures++))
        fi
    done < <(echo "$selected_instances" | jq -c '.[]')
    
    if [[ $termination_failures -gt 0 ]]; then
        log_error "Instance rotation completed with $termination_failures failure(s)"
        return 1
    else
        log_success "Instance rotation completed successfully for shape: $shape"
        return 0
    fi
}

# Main lifecycle management function
manage_instance_lifecycle() {
    local compartment_id="$1"
    local dry_run="${2:-$DRY_RUN}"
    
    log_info "Starting instance lifecycle management"
    
    # Initialize lifecycle manager
    if ! init_lifecycle_manager; then
        log_error "Failed to initialize lifecycle manager"
        return 1
    fi
    
    # Load configuration
    get_lifecycle_config
    
    # Check if auto-rotation is enabled
    if [[ "$AUTO_ROTATE_INSTANCES" != "true" ]]; then
        log_info "Auto-rotation is disabled (AUTO_ROTATE_INSTANCES=false)"
        return 0
    fi
    
    log_info "Auto-rotation enabled - checking for instances requiring lifecycle management"
    
    # Define shapes to manage
    local shapes=("VM.Standard.A1.Flex" "VM.Standard.E2.1.Micro")
    local rotation_failures=0
    
    for shape in "${shapes[@]}"; do
        log_info "Processing lifecycle management for shape: $shape"
        
        if ! rotate_instances_for_shape "$shape" "$compartment_id" "$dry_run"; then
            log_error "Lifecycle management failed for shape: $shape"
            ((rotation_failures++))
        fi
    done
    
    # Summary
    if [[ $rotation_failures -eq 0 ]]; then
        log_success "Instance lifecycle management completed successfully"
        return 0
    else
        log_error "Instance lifecycle management completed with $rotation_failures failure(s)"
        return 1
    fi
}

# Print lifecycle statistics
print_lifecycle_statistics() {
    if [[ ! -f "$LIFECYCLE_STATE_FILE" ]]; then
        log_info "No lifecycle statistics available"
        return 0
    fi
    
    local stats
    stats=$(cat "$LIFECYCLE_STATE_FILE")
    
    local total_rotations last_rotation
    total_rotations=$(echo "$stats" | jq -r '.statistics.total_rotations // 0')
    last_rotation=$(echo "$stats" | jq -r '.last_rotation // "never"')
    
    log_info "Lifecycle Management Statistics:"
    log_info "  Total rotations: $total_rotations"
    log_info "  Last rotation: $last_rotation"
    
    # Recent activity (last 10 actions)
    local recent_count
    recent_count=$(echo "$stats" | jq '.instances | length')
    
    if [[ $recent_count -gt 0 ]]; then
        log_info "  Recent activity:"
        echo "$stats" | jq -r '.instances[-10:] | .[] | "    \(.timestamp): \(.action) \(.instance_name) (\(.instance_id))"'
    fi
}

# Command-line interface
main() {
    local command="${1:-help}"
    local compartment_id="${OCI_COMPARTMENT_ID:-}"
    
    case "$command" in
        "manage")
            if [[ -z "$compartment_id" ]]; then
                log_error "OCI_COMPARTMENT_ID environment variable is required"
                exit 1
            fi
            manage_instance_lifecycle "$compartment_id" "${2:-false}"
            ;;
        "dry-run")
            if [[ -z "$compartment_id" ]]; then
                log_error "OCI_COMPARTMENT_ID environment variable is required"
                exit 1
            fi
            log_info "Running lifecycle management in DRY RUN mode"
            manage_instance_lifecycle "$compartment_id" "true"
            ;;
        "stats")
            print_lifecycle_statistics
            ;;
        "list")
            if [[ -z "$compartment_id" ]]; then
                log_error "OCI_COMPARTMENT_ID environment variable is required"
                exit 1
            fi
            get_instance_list "$compartment_id" | jq '.'
            ;;
        "help"|*)
            echo "Oracle Instance Lifecycle Management"
            echo ""
            echo "Usage: $0 <command> [options]"
            echo ""
            echo "Commands:"
            echo "  manage     - Run lifecycle management (respects AUTO_ROTATE_INSTANCES setting)"
            echo "  dry-run    - Run lifecycle management in dry-run mode (no actual terminations)"
            echo "  stats      - Display lifecycle management statistics"
            echo "  list       - List all instances in the compartment"
            echo "  help       - Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  AUTO_ROTATE_INSTANCES     - Enable automatic rotation (true/false, default: false)"
            echo "  INSTANCE_MIN_AGE_HOURS    - Minimum age before rotation (hours, default: 24)"
            echo "  ROTATION_STRATEGY         - Strategy: oldest_first, least_utilized (default: oldest_first)"
            echo "  HEALTH_CHECK_ENABLED      - Enable health checks (true/false, default: true)"
            echo "  DRY_RUN                   - Dry run mode (true/false, default: false)"
            echo ""
            echo "Examples:"
            echo "  AUTO_ROTATE_INSTANCES=true $0 manage"
            echo "  INSTANCE_MIN_AGE_HOURS=48 ROTATION_STRATEGY=least_utilized $0 dry-run"
            echo "  $0 stats"
            ;;
    esac
}

# Execute main function if script is called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi