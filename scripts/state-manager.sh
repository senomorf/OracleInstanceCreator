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

# =============================================================================
# STATE FILE MANAGEMENT
# =============================================================================

# Generate cache key for GitHub Actions cache
# Format: oci-instances-{region}-{version}-{date}
generate_cache_key() {
    local region="${OCI_REGION:-unknown}"
    local date_key
    date_key=$(date '+%Y-%m-%d')
    
    # Sanitize region for cache key (replace special chars with hyphens)
    local sanitized_region
    sanitized_region=$(echo "$region" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
    
    echo "oci-instances-${sanitized_region}-${CACHE_VERSION}-${date_key}"
}

# Generate fallback cache key pattern for restore
generate_cache_restore_keys() {
    local region="${OCI_REGION:-unknown}"
    local sanitized_region
    sanitized_region=$(echo "$region" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
    
    # Generate keys for today and yesterday (in case of timezone differences)
    local today yesterday
    today=$(date '+%Y-%m-%d')
    yesterday=$(date -d 'yesterday' '+%Y-%m-%d' 2>/dev/null || date -v-1d '+%Y-%m-%d' 2>/dev/null || echo "$today")
    
    echo "oci-instances-${sanitized_region}-${CACHE_VERSION}-${today}"
    echo "oci-instances-${sanitized_region}-${CACHE_VERSION}-${yesterday}"
    echo "oci-instances-${sanitized_region}-${CACHE_VERSION}-"
}

# Initialize empty state file
init_state_file() {
    local state_file="$1"
    
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
    local state_file="${1:-$STATE_FILE_NAME}"
    
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
    local state_file="${2:-$STATE_FILE_NAME}"
    
    if [[ ! -f "$state_file" ]]; then
        return 1
    fi
    
    jq -e --arg name "$instance_name" '.instances[$name] != null' "$state_file" >/dev/null 2>&1
}

# Get instance state information
get_instance_state() {
    local instance_name="$1" 
    local state_file="${2:-$STATE_FILE_NAME}"
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

# Add or update instance in state
update_instance_state() {
    local instance_name="$1"
    local ocid="$2"
    local status="${3:-created}"
    local state_file="${4:-$STATE_FILE_NAME}"
    
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

# Remove instance from state  
remove_instance_state() {
    local instance_name="$1"
    local state_file="${2:-$STATE_FILE_NAME}"
    
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

# =============================================================================
# CACHE VALIDATION
# =============================================================================

# Check if state is expired based on TTL
is_state_expired() {
    local state_file="${1:-$STATE_FILE_NAME}"
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
    local state_file="${1:-$STATE_FILE_NAME}"
    
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
    local state_file="${1:-$STATE_FILE_NAME}"
    
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
    
    # GitHub Actions cache save requires the file to be in current directory
    # or a subdirectory, so we may need to copy it
    local cache_dir=".cache/oci-state"
    mkdir -p "$cache_dir"
    cp "$state_file" "$cache_dir/"
    
    # Note: Actual cache save would be handled by GitHub Actions workflow
    # This function prepares the file for caching
    echo "CACHE_KEY=$cache_key" >> "${GITHUB_ENV:-/dev/null}"
    echo "CACHE_PATH=$cache_dir" >> "${GITHUB_ENV:-/dev/null}"
    
    log_debug "State prepared for caching in: $cache_dir"
}

# Load state from GitHub Actions cache (if available)
load_state_from_cache() {
    local state_file="${1:-$STATE_FILE_NAME}"
    
    if [[ "$(get_cache_enabled)" != "true" ]]; then
        log_debug "Cache disabled, skipping load"
        return 1
    fi
    
    if ! is_github_actions; then
        log_debug "Not in GitHub Actions, skipping cache load"
        return 1
    fi
    
    local cache_dir=".cache/oci-state"
    local cached_state="$cache_dir/$STATE_FILE_NAME"
    
    if [[ -f "$cached_state" ]]; then
        if validate_state_file "$cached_state"; then
            cp "$cached_state" "$state_file"
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
    local state_file="${1:-$STATE_FILE_NAME}"
    
    log_debug "Initializing state manager (cache enabled: $(get_cache_enabled), TTL: $(get_cache_ttl_hours)h)"
    
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
    local state_file="${2:-$STATE_FILE_NAME}"
    
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
    local state_file="${3:-$STATE_FILE_NAME}"
    
    update_instance_state "$instance_name" "$ocid" "created" "$state_file"
    save_state_to_cache "$state_file"
}

# Record instance verification 
record_instance_verification() {
    local instance_name="$1"
    local ocid="$2"
    local status="${3:-verified}"
    local state_file="${4:-$STATE_FILE_NAME}"
    
    update_instance_state "$instance_name" "$ocid" "$status" "$state_file"
    save_state_to_cache "$state_file"
}

# Clean up state management
cleanup_state_manager() {
    local state_file="${1:-$STATE_FILE_NAME}"
    
    # Cleanup temporary files
    rm -f "${state_file}.tmp" "${state_file}.bak"
    
    log_debug "State manager cleanup completed"
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Get state summary for logging
get_state_summary() {
    local state_file="${1:-$STATE_FILE_NAME}"
    
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
    local state_file="${1:-$STATE_FILE_NAME}"
    
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
        *)
            echo "Usage: $0 {init|check|record|verify|print|cleanup} [args...]" >&2
            echo "  init [state_file]                           - Initialize state manager"
            echo "  check <instance_name> [state_file]          - Check if instance should be created"
            echo "  record <instance_name> <ocid> [state_file]  - Record successful creation"
            echo "  verify <name> <ocid> [status] [state_file]  - Record verification"
            echo "  print [state_file]                          - Print current state"
            echo "  cleanup [state_file]                        - Cleanup temporary files"
            exit 1
            ;;
    esac
}

# Run main if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi