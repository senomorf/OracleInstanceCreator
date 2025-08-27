#!/bin/bash
# ShellSpec helper functions for Oracle Instance Creator tests

# Mock OCI CLI for testing
mock_oci_cli() {
    case "$1" in
        "iam" | "compute" | "network")
            echo '{"data": {"id": "ocid1.test.example"}}'
            ;;
        *)
            echo "Unknown OCI command: $1" >&2
            return 1
            ;;
    esac
}

# Mock environment for testing
setup_test_env() {
    export OCI_TENANCY_OCID="ocid1.tenancy.test"
    export OCI_USER_OCID="ocid1.user.test" 
    export OCI_REGION="us-phoenix-1"
    export OCI_COMPARTMENT_OCID="ocid1.compartment.test"
    export DEBUG="true"
}

# Clean up test environment
cleanup_test_env() {
    unset OCI_TENANCY_OCID OCI_USER_OCID OCI_REGION OCI_COMPARTMENT_OCID DEBUG
}

# Create temporary test files
create_test_files() {
    local test_dir="$1"
    mkdir -p "$test_dir"
    echo "test content" > "$test_dir/test_file.txt"
}

# Verify OCI OCID format
verify_ocid_format() {
    local ocid="$1"
    [[ "$ocid" =~ ^ocid1\.[a-z]+\.[a-z0-9-]+\.[a-z0-9-]+\..+ ]]
}