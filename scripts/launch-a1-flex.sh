#!/bin/bash

# A1.Flex (ARM) specific launcher script
# Sets environment variables for VM.Standard.A1.Flex shape and delegates to launch-instance.sh

set -euo pipefail

# Get the directory containing this script
SCRIPT_DIR="$(dirname "$0")"

# Source constants for shape configurations
source "$SCRIPT_DIR/constants.sh"

# Set A1.Flex specific environment variables
export OCI_SHAPE="$A1_FLEX_SHAPE"
export OCI_OCPUS="$A1_FLEX_OCPUS"
export OCI_MEMORY_IN_GBS="$A1_FLEX_MEMORY_GB"
export INSTANCE_DISPLAY_NAME="$A1_FLEX_INSTANCE_NAME"

# Delegate to the main launch script
exec "$SCRIPT_DIR/launch-instance.sh" "$@"