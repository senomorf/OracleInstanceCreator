#!/bin/bash

# E2.1.Micro (AMD) specific launcher script
# Sets environment variables for VM.Standard.E2.1.Micro shape and delegates to launch-instance.sh

set -euo pipefail

# Get the directory containing this script
SCRIPT_DIR="$(dirname "$0")"

# Source constants for shape configurations
source "$SCRIPT_DIR/constants.sh"

# Set E2.1.Micro specific environment variables
export OCI_SHAPE="$E2_MICRO_SHAPE"
export OCI_OCPUS="$E2_MICRO_OCPUS"
export OCI_MEMORY_IN_GBS="$E2_MICRO_MEMORY_GB"
export INSTANCE_DISPLAY_NAME="$E2_MICRO_INSTANCE_NAME"

# Delegate to the main launch script
exec "$SCRIPT_DIR/launch-instance.sh" "$@"