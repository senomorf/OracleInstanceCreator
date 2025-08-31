#!/bin/bash
# State Management for Oracle Instance Creator
# Manages instance state caching via GitHub Actions cache to reduce Oracle API calls
# Provides functions for storing, retrieving, and validating instance creation state

set -euo pipefail

# Source common utilities (which includes constants.sh)
source "$(dirname "${BASH_SOURCE[0]:-$0}")/utils.sh"

# =============================================================================
# CACHE CONFIGURATION (constants defined in constants.sh)
# =============================================================================

# Get cache configuration from environment with validation
get_cache_enabled() {
    local enabled="${CACHE_ENABLED:-$CACHE_ENABLED_DEFAULT}"
    if [[ "$enabled" =~ ^(true|false)$ ]]; then
        echo "$enabled"
    else
        echo "$CACHE_ENABLED_DEFAULT"
    fi
}

get_cache_ttl_hours() {
    local ttl="${CACHE_TTL_HOURS:-$CACHE_TTL_HOURS_DEFAULT}"
    if [[ "$ttl" =~ ^[0-9]+$ ]] && [[ "$ttl" -ge 1 ]] && [[ "$ttl" -le 168 ]]; then  # 1-168 hours (1 week max)
        echo "$ttl"
    else
        echo "$CACHE_TTL_HOURS_DEFAULT"
    fi
}

# Get dynamic TTL based on region contention
get_dynamic_ttl_hours() {
    local base_ttl
    base_ttl=$(get_cache_ttl_hours)
    local region="${OCI_REGION:-}"
    
    # Check if current region is in high contention list
    if [[ ",$HIGH_CONTENTION_REGIONS," == *",$region,"* ]]; then
        # Use reduced TTL for high-contention regions
        local reduced_ttl
        reduced_ttl=$(echo "$base_ttl * $HIGH_CONTENTION_TTL_MULTIPLIER" | bc 2>/dev/null || echo "$base_ttl")
        # Ensure minimum TTL of 1 hour
        if (( $(echo "$reduced_ttl < 1" | bc -l 2>/dev/null || echo "0") )); then
            echo "1"
        else
            printf "%.0f" "$reduced_ttl"
        fi
    else
        echo "$base_ttl"
    fi
}

# Get absolute cache directory path
get_cache_dir() {
    local cache_dir="${CACHE_PATH:-$CACHE_PATH_DEFAULT}"
    # Convert to absolute path if relative
    if [[ "$cache_dir" != /* ]]; then
        cache_dir="$(pwd)/$cache_dir"
    fi
    echo "$cache_dir"
}

# Get absolute state file path
get_state_file_path() {
    local state_file
    state_file="${1:-$STATE_FILE_NAME}"
    local cache_dir
    cache_dir=$(get_cache_dir)
    
    # If state_file is just a filename, put it in cache directory
    if [[ "$state_file" == "$(basename "$state_file")" ]]; then
        echo "$cache_dir/$state_file"
    else
        # If it's already a path, use it as-is but make it absolute
        if [[ "$state_file" != /* ]]; then
            echo "$(pwd)/$state_file"
        else
            echo "$state_file"
        fi
    fi
}

# =============================================================================
# STATE FILE MANAGEMENT
# =============================================================================

# File locking utilities for safe concurrent access
acquire_state_lock() {
    local state_file="$1"
    local lock_file="${state_file}.lock"
    local timeout="${2:-30}"  # Default 30 second timeout
    local wait_count=0
    
    # Try to acquire lock with timeout
    while (( wait_count < timeout )); do
        if (set -C; echo $$ > "$lock_file") 2>/dev/null; then
            log_debug "Acquired state lock: $lock_file"
            return 0
        fi
        
        # Check if lock is stale (older than 5 minutes)
        if [[ -f "$lock_file" ]] && [[ $(( $(date +%s) - $(stat -c %Y "$lock_file" 2>/dev/null || stat -f %m "$lock_file" 2>/dev/null || echo 0) )) -gt 300 ]]; then
            log_warning "Removing stale lock file: $lock_file"
            rm -f "$lock_file"
            continue
        fi
        
        log_debug "Waiting for state lock... ($((wait_count + 1))/$timeout)"
        sleep 1
        ((wait_count++))
    done
    
    log_error "Failed to acquire state lock after ${timeout}s: $lock_file"
    return 1
}

release_state_lock() {
    local state_file="$1"
    local lock_file="${state_file}.lock"
    
    if [[ -f "$lock_file" ]]; then
        rm -f "$lock_file"
        log_debug "Released state lock: $lock_file"
    fi
}

# Wrapper for safe state file operations with automatic locking
with_state_lock() {
    local state_file="$1"
    shift
    local func_name="$1"
    shift
    
    if acquire_state_lock "$state_file"; then
        # Ensure lock is released even if function fails
        # shellcheck disable=SC2064
        trap "release_state_lock '$state_file'" EXIT ERR
        "$func_name" "$state_file" "$@"
        local result=$?
        release_state_lock "$state_file"
        trap - EXIT ERR
        return $result
    else
        log_error "Failed to acquire lock for state operation: $func_name"
        return 1
    fi
}

# Generate cache key for GitHub Actions cache
# Format: oci-instances-{region_hash}-{version}-{date}
generate_cache_key() {
    local region="${OCI_REGION:-unknown}"
    local date_key
    
    # Use provided cache date key if available (prevents race conditions)
    if [[ -n "${CACHE_DATE_KEY:-}" ]]; then
        date_key="$CACHE_DATE_KEY"
    else
        date_key=$(date '+%Y-%m-%d')
    fi
    
    # Generate secure hash of region to avoid information leakage
    local region_hash
    if command -v sha256sum >/dev/null 2>&1; then
        region_hash=$(echo -n "$region" | sha256sum | cut -d' ' -f1 | head -c 8)
    elif command -v shasum >/dev/null 2>&1; then
        region_hash=$(echo -n "$region" | shasum -a 256 | cut -d' ' -f1 | head -c 8)
    else
        # Fallback to simple sanitization if no hash tools available
        region_hash=$(echo "$region" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
    fi
    
    echo "oci-instances-${region_hash}-${CACHE_VERSION}-${date_key}"
}

# Generate fallback cache key pattern for restore
generate_cache_restore_keys() {
    local region="${OCI_REGION:-unknown}"
    
    # Generate secure hash of region to match generate_cache_key behavior
    local region_hash
    if command -v sha256sum >/dev/null 2>&1; then
        region_hash=$(echo -n "$region" | sha256sum | cut -d' ' -f1 | head -c 8)
    elif command -v shasum >/dev/null 2>&1; then
        region_hash=$(echo -n "$region" | shasum -a 256 | cut -d' ' -f1 | head -c 8)
    else
        # Fallback to simple sanitization if no hash tools available
        region_hash=$(echo "$region" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
    fi
    
    # Generate keys for today and yesterday (in case of timezone differences)
    local today yesterday
    today=$(date '+%Y-%m-%d')
    yesterday=$(date -d 'yesterday' '+%Y-%m-%d' 2>/dev/null || date -v-1d '+%Y-%m-%d' 2>/dev/null || echo "$today")
    
    echo "oci-instances-${region_hash}-${CACHE_VERSION}-${today}"
    echo "oci-instances-${region_hash}-${CACHE_VERSION}-${yesterday}"
    echo "oci-instances-${region_hash}-${CACHE_VERSION}-"
}

# Initialize empty state file
init_state_file() {
    local state_file="$1"
    
    # Ensure the directory exists
    local state_dir
    state_dir=$(dirname "$state_file")
    if [[ ! -d "$state_dir" ]]; then
        mkdir -p "$state_dir"
        log_debug "Created state directory: $state_dir"
    fi
    
    local timestamp
    timestamp=$(date +%s)
    
    cat > "$state_file" << EOF
{
  "version": "$CACHE_VERSION",
  "region": "${OCI_REGION:-}",
  "created": "$timestamp",
  "updated": "$timestamp",
  "instances": {}
}
EOF
    
    log_debug "Initialized empty state file: $state_file"
}

# Load state from file with validation
load_state() {
    local state_file
    state_file=$(get_state_file_path "${1:-}")
    
    if [[ ! -f "$state_file" ]]; then
        log_debug "State file not found, initializing: $state_file"
        init_state_file "$state_file"
    fi
    
    # Validate JSON structure
    if ! jq empty "$state_file" 2>/dev/null; then
        log_warning "Invalid JSON in state file, reinitializing: $state_file"
        init_state_file "$state_file"
    fi
    
    # Ensure required fields exist
    if ! jq -e '.instances' "$state_file" >/dev/null 2>&1; then
        log_warning "State file missing instances field, reinitializing: $state_file"
        init_state_file "$state_file"
    fi
    
    echo "$state_file"
}

# =============================================================================
# INSTANCE STATE OPERATIONS
# =============================================================================

# Check if instance exists in state
instance_exists_in_state() {
    local instance_name="$1"
    local state_file
    state_file=$(get_state_file_path "${2:-}")
    
    if [[ ! -f "$state_file" ]]; then
        return 1
    fi
    
    jq -e --arg name "$instance_name" '.instances[$name] != null' "$state_file" >/dev/null 2>&1
}

# Get instance state information
get_instance_state() {
    local instance_name="$1" 
    local state_file
    state_file=$(get_state_file_path "${2:-}")
    local field="${3:-}"  # Optional: specific field to retrieve
    
    if [[ ! -f "$state_file" ]]; then
        return 1
    fi
    
    if [[ -n "$field" ]]; then
        jq -r --arg name "$instance_name" --arg field "$field" \
           '.instances[$name][$field] // empty' "$state_file" 2>/dev/null || echo ""
    else
        jq -r --arg name "$instance_name" \
           '.instances[$name] // empty' "$state_file" 2>/dev/null || echo "{}"
    fi
}

# Internal function - performs actual state update (assumes lock is held)
_update_instance_state_locked() {
    local state_file="$1"
    local instance_name="$2"
    local ocid="$3"
    local status="${4:-created}"
    
    local timestamp
    timestamp=$(date +%s)
    
    # Ensure state file exists
    load_state "$state_file" >/dev/null
    
    # Update instance state
    local temp_file
    temp_file=$(mktemp)
    
    jq --arg name "$instance_name" \
       --arg ocid "$ocid" \
       --arg status "$status" \
       --arg timestamp "$timestamp" \
       '.updated = $timestamp | .instances[$name] = {
         "ocid": $ocid,
         "status": $status, 
         "created": ($timestamp),
         "last_verified": $timestamp,
         "shape": (env.OCI_SHAPE // ""),
         "region": (env.OCI_REGION // "")
       }' "$state_file" > "$temp_file"
    
    mv "$temp_file" "$state_file"
    
    log_info "Updated instance state: $instance_name (OCID: $ocid, Status: $status)"
}

# Add or update instance in state with file locking
update_instance_state() {
    local instance_name="$1"
    local ocid="$2"
    local status="${3:-created}"
    local state_file
    state_file=$(get_state_file_path "${4:-}")
    
    with_state_lock "$state_file" _update_instance_state_locked "$instance_name" "$ocid" "$status"
}

# Internal function - performs actual state removal (assumes lock is held)
_remove_instance_state_locked() {
    local state_file="$1"
    local instance_name="$2"
    
    if [[ ! -f "$state_file" ]]; then
        log_debug "State file not found, nothing to remove: $state_file"
        return 0
    fi
    
    local temp_file
    temp_file=$(mktemp)
    
    local timestamp
    timestamp=$(date +%s)
    
    jq --arg name "$instance_name" \
       --arg timestamp "$timestamp" \
       '.updated = $timestamp | del(.instances[$name])' "$state_file" > "$temp_file"
    
    mv "$temp_file" "$state_file"
    
    log_info "Removed instance from state: $instance_name"
}

# Remove instance from state with file locking
remove_instance_state() {
    local instance_name="$1"
    local state_file
    state_file=$(get_state_file_path "${2:-}")
    
    with_state_lock "$state_file" _remove_instance_state_locked "$instance_name"
}

# =============================================================================
# CACHE VALIDATION
# =============================================================================

# Check if state is expired based on TTL
is_state_expired() {
    local state_file
    state_file=$(get_state_file_path "${1:-}")
    local ttl_hours
    ttl_hours=$(get_cache_ttl_hours)
    
    if [[ ! -f "$state_file" ]]; then
        return 0  # No state file = expired
    fi
    
    local updated_timestamp
    updated_timestamp=$(jq -r '.updated // empty' "$state_file" 2>/dev/null)
    
    if [[ -z "$updated_timestamp" ]]; then
        return 0  # No timestamp = expired
    fi
    
    # Calculate expiry time using Unix timestamps (simpler and more reliable)
    local updated_epoch current_epoch ttl_seconds expiry_epoch
    current_epoch=$(date +%s)
    
    # Timestamp is already in Unix epoch format
    if [[ "$updated_timestamp" =~ ^[0-9]+$ ]]; then
        updated_epoch="$updated_timestamp"
    else
        # Fallback: assume expired if not a valid Unix timestamp
        log_debug "Invalid Unix timestamp format: $updated_timestamp"
        return 0  # Treat as expired
    fi
    
    ttl_seconds=$((ttl_hours * 3600))
    expiry_epoch=$((updated_epoch + ttl_seconds))
    
    if [[ "$current_epoch" -gt "$expiry_epoch" ]]; then
        log_debug "State cache expired (TTL: ${ttl_hours}h, Updated: $updated_timestamp)"
        return 0  # Expired
    else
        log_debug "State cache valid (TTL: ${ttl_hours}h, Updated: $updated_timestamp)"
        return 1  # Not expired
    fi
}

# Validate state file integrity and consistency
validate_state_file() {
    local state_file
    state_file=$(get_state_file_path "${1:-}")
    
    if [[ ! -f "$state_file" ]]; then
        log_debug "State file not found: $state_file"
        return 1
    fi
    
    # Check JSON validity
    if ! jq empty "$state_file" 2>/dev/null; then
        log_warning "Invalid JSON in state file: $state_file"
        return 1
    fi
    
    # Check required structure
    local required_fields=("version" "instances")
    for field in "${required_fields[@]}"; do
        if ! jq -e ".$field" "$state_file" >/dev/null 2>&1; then
            log_warning "Missing required field '$field' in state file: $state_file"
            return 1
        fi
    done
    
    # Check version compatibility
    local state_version
    state_version=$(jq -r '.version // ""' "$state_file")
    if [[ "$state_version" != "$CACHE_VERSION" ]]; then
        log_warning "State file version mismatch (expected: $CACHE_VERSION, got: $state_version)"
        return 1
    fi
    
    log_debug "State file validation passed: $state_file"
    return 0
}

# =============================================================================
# GITHUB ACTIONS INTEGRATION
# =============================================================================

# Check if running in GitHub Actions environment
is_github_actions() {
    [[ -n "${GITHUB_ACTIONS:-}" ]] && [[ "${GITHUB_ACTIONS}" == "true" ]]
}

# Save state to GitHub Actions cache (if available)
save_state_to_cache() {
    local state_file
    state_file=$(get_state_file_path "${1:-}")
    
    if [[ "$(get_cache_enabled)" != "true" ]]; then
        log_debug "Cache disabled, skipping save"
        return 0
    fi
    
    if ! is_github_actions; then
        log_debug "Not in GitHub Actions, skipping cache save"
        return 0
    fi
    
    if [[ ! -f "$state_file" ]]; then
        log_warning "State file not found, cannot save to cache: $state_file"
        return 1
    fi
    
    local cache_key
    cache_key=$(generate_cache_key)
    
    log_info "Saving state to GitHub Actions cache: $cache_key"
    
    # Ensure the cache directory exists and copy state file
    local cache_dir
    cache_dir=$(get_cache_dir)
    mkdir -p "$cache_dir"
    
    # If state file is already in cache directory, no need to copy
    local cached_state="$cache_dir/$STATE_FILE_NAME"
    if [[ "$state_file" != "$cached_state" ]]; then
        cp "$state_file" "$cached_state"
        log_debug "Copied state file to cache directory: $cached_state"
    fi
    
    # Note: Actual cache save would be handled by GitHub Actions workflow
    # This function prepares the file for caching
    echo "CACHE_KEY=$cache_key" >> "${GITHUB_ENV:-/dev/null}"
    echo "CACHE_PATH=$cache_dir" >> "${GITHUB_ENV:-/dev/null}"
    
    log_debug "State prepared for caching in: $cache_dir"
}

# Load state from GitHub Actions cache (if available)
load_state_from_cache() {
    local state_file
    state_file=$(get_state_file_path "${1:-}")
    
    if [[ "$(get_cache_enabled)" != "true" ]]; then
        log_debug "Cache disabled, skipping load"
        return 1
    fi
    
    if ! is_github_actions; then
        log_debug "Not in GitHub Actions, skipping cache load"
        return 1
    fi
    
    local cache_dir
    cache_dir=$(get_cache_dir)
    local cached_state="$cache_dir/$STATE_FILE_NAME"
    
    if [[ -f "$cached_state" ]]; then
        if validate_state_file "$cached_state"; then
            # Ensure target directory exists
            local target_dir
            target_dir=$(dirname "$state_file")
            if [[ ! -d "$target_dir" ]]; then
                mkdir -p "$target_dir"
            fi
            
            # If state file is the same as cached state, no need to copy
            if [[ "$state_file" != "$cached_state" ]]; then
                cp "$cached_state" "$state_file"
                log_debug "Copied cached state to: $state_file"
            fi
            
            log_info "Loaded state from GitHub Actions cache"
            return 0
        else
            log_warning "Cached state file invalid, ignoring cache"
            return 1
        fi
    else
        log_debug "No cached state found in: $cache_dir"
        return 1
    fi
}

# =============================================================================
# HIGH-LEVEL INTERFACE FUNCTIONS
# =============================================================================

# Initialize state management system
init_state_manager() {
    local state_file
    state_file=$(get_state_file_path "${1:-}")
    
    log_debug "Initializing state manager (cache enabled: $(get_cache_enabled), TTL: $(get_dynamic_ttl_hours)h)"
    
    # Try to load from cache first
    if ! load_state_from_cache "$state_file"; then
        # Fallback to initializing empty state
        load_state "$state_file" >/dev/null
    fi
    
    echo "$state_file"
}

# Check if instance should be created (not in cache or cache expired)
should_create_instance() {
    local instance_name="$1"
    local state_file
    state_file=$(get_state_file_path "${2:-}")
    
    # If cache disabled, always create
    if [[ "$(get_cache_enabled)" != "true" ]]; then
        log_debug "Cache disabled, allowing instance creation: $instance_name"
        return 0
    fi
    
    # If state expired, allow creation
    if is_state_expired "$state_file"; then
        log_debug "State expired, allowing instance creation: $instance_name"
        return 0
    fi
    
    # If instance not in state, allow creation
    if ! instance_exists_in_state "$instance_name" "$state_file"; then
        log_debug "Instance not in state, allowing creation: $instance_name"
        return 0
    fi
    
    # Check instance status
    local status
    status=$(get_instance_state "$instance_name" "$state_file" "status")
    
    case "$status" in
        "created"|"verified"|"running")
            log_info "Instance exists in state with status '$status', skipping creation: $instance_name"
            return 1  # Don't create
            ;;
        "failed"|"terminated")
            log_info "Instance exists in state with status '$status', allowing recreation: $instance_name"
            return 0  # Allow creation
            ;;
        *)
            log_debug "Instance exists in state with unknown status '$status', allowing creation: $instance_name"
            return 0  # Allow creation for safety
            ;;
    esac
}

# Record successful instance creation
record_instance_creation() {
    local instance_name="$1"
    local ocid="$2"
    local state_file
    state_file=$(get_state_file_path "${3:-}")
    
    update_instance_state "$instance_name" "$ocid" "created" "$state_file"
    save_state_to_cache "$state_file"
}

# Record instance verification 
record_instance_verification() {
    local instance_name="$1"
    local ocid="$2"
    local status="${3:-verified}"
    local state_file
    state_file=$(get_state_file_path "${4:-}")
    
    update_instance_state "$instance_name" "$ocid" "$status" "$state_file"
    save_state_to_cache "$state_file"
}

# Clean up state management
cleanup_state_manager() {
    local state_file
    state_file=$(get_state_file_path "${1:-}")
    
    # Cleanup temporary files
    rm -f "${state_file}.tmp" "${state_file}.bak"
    
    log_debug "State manager cleanup completed"
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Get state summary for logging
get_state_summary() {
    local state_file
    state_file=$(get_state_file_path "${1:-}")
    
    if [[ ! -f "$state_file" ]]; then
        echo "No state file"
        return
    fi
    
    local instance_count created_count updated
    instance_count=$(jq -r '.instances | length' "$state_file" 2>/dev/null || echo "0")
    created_count=$(jq -r '.instances | to_entries | map(select(.value.status == "created")) | length' "$state_file" 2>/dev/null || echo "0")
    local updated updated_readable
    updated=$(jq -r '.updated // "unknown"' "$state_file" 2>/dev/null)
    
    # Convert Unix timestamp to readable format for display
    if [[ "$updated" =~ ^[0-9]+$ ]] && [[ "$updated" != "unknown" ]]; then
        updated_readable=$(date -r "$updated" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || echo "$updated")
    else
        updated_readable="$updated"
    fi
    
    echo "Instances: $instance_count (created: $created_count), Updated: $updated_readable"
}

# Print state in human-readable format
print_state() {
    local state_file
    state_file=$(get_state_file_path "${1:-}")
    
    if [[ ! -f "$state_file" ]]; then
        echo "No state file found: $state_file"
        return 1
    fi
    
    echo "=== Instance State Summary ==="
    echo "Cache enabled: $(get_cache_enabled)"
    echo "Cache TTL: $(get_cache_ttl_hours) hours" 
    echo "State file: $state_file"
    echo "Summary: $(get_state_summary "$state_file")"
    echo
    
    if jq -e '.instances | length > 0' "$state_file" >/dev/null 2>&1; then
        echo "=== Instance Details ==="
        # Process each instance and format timestamps
        while IFS= read -r line; do
            local name status ocid created
            name=$(echo "$line" | jq -r '.key')
            status=$(echo "$line" | jq -r '.value.status')
            ocid=$(echo "$line" | jq -r '.value.ocid')
            created=$(echo "$line" | jq -r '.value.created')
            
            # Convert Unix timestamp to readable format
            local created_readable
            if [[ "$created" =~ ^[0-9]+$ ]]; then
                created_readable=$(date -r "$created" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || echo "$created")
            else
                created_readable="$created"
            fi
            
            echo "$name: $status (OCID: $ocid, Created: $created_readable)"
        done < <(jq -c '.instances | to_entries[]' "$state_file")
    else
        echo "No instances in state"
    fi
}

# =============================================================================
# ENHANCED VERIFICATION FUNCTIONS
# =============================================================================

# Verify instance configuration matches cached expectations
verify_instance_configuration() {
    local instance_id="$1"
    local expected_shape="$2"
    local expected_ocpus="${3:-}"
    local expected_memory="${4:-}"
    
    if [[ -z "$instance_id" || -z "$expected_shape" ]]; then
        log_error "verify_instance_configuration: instance_id and expected_shape are required"
        return 1
    fi
    
    # Get actual instance configuration from OCI API
    local actual_config
    if ! actual_config=$(oci_cmd compute instance get --instance-id "$instance_id" \
        --query 'data.{shape:shape,ocpus:shapeConfig.ocpus,memory:shapeConfig.memoryInGBs}' \
        --output json 2>/dev/null); then
        log_error "Failed to get instance configuration for $instance_id"
        return 1
    fi
    
    # Parse the configuration
    local actual_shape actual_ocpus actual_memory
    actual_shape=$(echo "$actual_config" | jq -r '.shape // "unknown"')
    actual_ocpus=$(echo "$actual_config" | jq -r '.ocpus // "null"')
    actual_memory=$(echo "$actual_config" | jq -r '.memory // "null"')
    
    # Verify shape matches
    if [[ "$actual_shape" != "$expected_shape" ]]; then
        log_warning "Instance shape mismatch: expected '$expected_shape', got '$actual_shape'"
        return 2
    fi
    
    # Verify OCPUs if specified and shape is flexible
    if [[ -n "$expected_ocpus" && "$actual_ocpus" != "null" ]]; then
        if ! awk -v actual="$actual_ocpus" -v expected="$expected_ocpus" \
            'BEGIN { exit (actual != expected) }' 2>/dev/null; then
            log_warning "Instance OCPUs mismatch: expected '$expected_ocpus', got '$actual_ocpus'"
            return 2
        fi
    fi
    
    # Verify memory if specified and shape is flexible
    if [[ -n "$expected_memory" && "$actual_memory" != "null" ]]; then
        if ! awk -v actual="$actual_memory" -v expected="$expected_memory" \
            'BEGIN { exit (actual != expected) }' 2>/dev/null; then
            log_warning "Instance memory mismatch: expected '${expected_memory}GB', got '${actual_memory}GB'"
            return 2
        fi
    fi
    
    log_debug "Instance configuration verified: shape=$actual_shape, ocpus=$actual_ocpus, memory=${actual_memory}GB"
    return 0
}

# Update instance state with configuration details
update_instance_state_with_config() {
    local instance_name="$1"
    local ocid="$2"
    local status="$3"
    local shape="$4"
    local ocpus="${5:-}"
    local memory="${6:-}"
    local state_file
    state_file=$(get_state_file_path "${7:-}")
    
    # Create configuration object
    local config_json="{\"shape\": \"$shape\""
    if [[ -n "$ocpus" ]]; then
        config_json="$config_json, \"ocpus\": $ocpus"
    fi
    if [[ -n "$memory" ]]; then
        config_json="$config_json, \"memory\": $memory"
    fi
    config_json="$config_json}"
    
    # Update instance state with configuration
    local timestamp
    timestamp=$(date +%s)
    
    local temp_file="${state_file}.tmp"
    if jq --arg name "$instance_name" \
          --arg ocid "$ocid" \
          --arg status "$status" \
          --arg timestamp "$timestamp" \
          --argjson config "$config_json" \
          '.instances[$name] = {
              "id": $ocid,
              "status": $status,
              "updated": ($timestamp | tonumber),
              "config": $config
          } | .updated = ($timestamp | tonumber)' \
          "$state_file" > "$temp_file"; then
        mv "$temp_file" "$state_file"
        log_debug "Updated instance state with configuration: $instance_name"
    else
        rm -f "$temp_file"
        log_error "Failed to update instance state with configuration: $instance_name"
        return 1
    fi
}

# =============================================================================
# CACHE STATISTICS AND MANAGEMENT
# =============================================================================

# Get cache statistics summary
get_cache_stats() {
    local cache_dir
    cache_dir=$(get_cache_dir)
    local stats_file="$cache_dir/$CACHE_STATS_FILE"
    
    if [[ ! -f "$stats_file" ]]; then
        echo "No cache statistics available"
        return 1
    fi
    
    echo "=== Cache Statistics ==="
    jq -r '.stats | to_entries | map("\(.key): \(.value)") | join("\n")' "$stats_file" 2>/dev/null || echo "Failed to read statistics"
    
    local updated
    updated=$(jq -r '.updated' "$stats_file" 2>/dev/null)
    if [[ "$updated" =~ ^[0-9]+$ ]]; then
        local updated_readable
        updated_readable=$(date -r "$updated" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || echo "$updated")
        echo "Last updated: $updated_readable"
    fi
}

# Purge cache and reset statistics
purge_cache() {
    local cache_dir
    cache_dir=$(get_cache_dir)
    
    if [[ -d "$cache_dir" ]]; then
        rm -rf "$cache_dir"
        log_info "Cache purged: $cache_dir"
    else
        log_debug "Cache directory does not exist: $cache_dir"
    fi
    
    # Reinitialize empty state
    init_state_manager >/dev/null
    log_info "Cache and state management reset"
}

# Check cache health
check_cache_health() {
    local cache_dir
    cache_dir=$(get_cache_dir)
    local state_file
    state_file=$(get_state_file_path)
    
    echo "=== Cache Health Check ==="
    
    # Check cache directory
    if [[ -d "$cache_dir" ]]; then
        echo "✓ Cache directory exists: $cache_dir"
        echo "  Permissions: $(stat -c %A "$cache_dir" 2>/dev/null || stat -f %Sp "$cache_dir" 2>/dev/null || echo "unknown")"
    else
        echo "✗ Cache directory missing: $cache_dir"
        return 1
    fi
    
    # Check state file
    if [[ -f "$state_file" ]]; then
        echo "✓ State file exists: $state_file"
        if validate_state_file "$state_file"; then
            echo "✓ State file is valid JSON"
            local ttl_hours
            ttl_hours=$(get_dynamic_ttl_hours)
            echo "  TTL: ${ttl_hours}h (dynamic based on region)"
            
            # Check if expired
            if is_state_expired "$state_file"; then
                echo "⚠ State file is expired"
            else
                echo "✓ State file is current"
            fi
        else
            echo "✗ State file is corrupted"
            return 1
        fi
    else
        echo "⚠ State file not found: $state_file"
    fi
    
    # Cache configuration
    echo "✓ Cache enabled: $(get_cache_enabled)"
    echo "✓ GitHub Actions mode: $(is_github_actions && echo "true" || echo "false")"
    
    return 0
}

# =============================================================================
# COMMAND LINE INTERFACE
# =============================================================================

# Main function for command-line usage
main() {
    case "${1:-}" in
        "init")
            init_state_manager "${2:-}"
            ;;
        "check")
            local instance_name="${2:-}"
            if [[ -z "$instance_name" ]]; then
                echo "Usage: $0 check <instance_name> [state_file]" >&2
                exit 1
            fi
            if should_create_instance "$instance_name" "${3:-}"; then
                echo "CREATE"
                exit 0
            else
                echo "SKIP"
                exit 1
            fi
            ;;
        "record")
            local instance_name="${2:-}"
            local ocid="${3:-}"
            if [[ -z "$instance_name" || -z "$ocid" ]]; then
                echo "Usage: $0 record <instance_name> <ocid> [state_file]" >&2
                exit 1
            fi
            record_instance_creation "$instance_name" "$ocid" "${4:-}"
            ;;
        "verify")
            local instance_name="${2:-}"
            local ocid="${3:-}"
            local status="${4:-verified}"
            if [[ -z "$instance_name" || -z "$ocid" ]]; then
                echo "Usage: $0 verify <instance_name> <ocid> [status] [state_file]" >&2
                exit 1
            fi
            record_instance_verification "$instance_name" "$ocid" "$status" "${5:-}"
            ;;
        "print")
            print_state "${2:-}"
            ;;
        "cleanup")
            cleanup_state_manager "${2:-}"
            ;;
        "stats")
            get_cache_stats
            ;;
        "health")
            check_cache_health
            ;;
        "purge")
            echo "WARNING: This will delete all cached data and reset statistics."
            if [[ "${2:-}" == "--confirm" ]]; then
                purge_cache
            else
                echo "To confirm, run: $0 purge --confirm"
                exit 1
            fi
            ;;
        "verify-config")
            local instance_id="${2:-}"
            local expected_shape="${3:-}"
            local expected_ocpus="${4:-}"
            local expected_memory="${5:-}"
            if [[ -z "$instance_id" || -z "$expected_shape" ]]; then
                echo "Usage: $0 verify-config <instance_id> <expected_shape> [expected_ocpus] [expected_memory]" >&2
                exit 1
            fi
            verify_instance_configuration "$instance_id" "$expected_shape" "$expected_ocpus" "$expected_memory"
            ;;
        *)
            echo "Usage: $0 {init|check|record|verify|print|cleanup|stats|health|purge|verify-config} [args...]" >&2
            echo ""
            echo "State Management:"
            echo "  init [state_file]                           - Initialize state manager"
            echo "  check <instance_name> [state_file]          - Check if instance should be created"
            echo "  record <instance_name> <ocid> [state_file]  - Record successful creation"
            echo "  verify <name> <ocid> [status] [state_file]  - Record verification"
            echo "  print [state_file]                          - Print current state"
            echo "  cleanup [state_file]                        - Cleanup temporary files"
            echo ""
            echo "Cache Management:"
            echo "  stats                                       - Show cache statistics"
            echo "  health                                      - Check cache health"
            echo "  purge --confirm                             - Purge cache and reset statistics"
            echo ""
            echo "Configuration Verification:"
            echo "  verify-config <id> <shape> [ocpus] [memory] - Verify instance configuration"
            exit 1
            ;;
    esac
}

# Run main if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
