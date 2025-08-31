# Instance Lifecycle Management

Oracle Instance Creator now includes automated instance lifecycle management and rotation capabilities, providing hands-off instance management for Oracle Cloud free tier automation.

## Overview

The instance lifecycle management system automatically handles Oracle Cloud free tier limits by:
- **Intelligent capacity detection**: Recognizes when shapes have reached their limits
- **Automated rotation**: Terminates older instances to free capacity for new deployments
- **Safety-first approach**: Multiple validation steps before any destructive operations
- **Configurable strategies**: Choose rotation strategy based on your preferences

## Key Features

### Automated Instance Rotation
- **Age-based rotation**: Terminate oldest instances when limits reached
- **Health-aware selection**: Consider instance health scores in rotation decisions
- **Configurable minimum age**: Prevent rotation of recently created instances
- **Multiple strategies**: `oldest_first` and `least_utilized` selection algorithms

### Safety and Control
- **Opt-in only**: Feature disabled by default, requires explicit enablement
- **Comprehensive validation**: Multiple safety checks before instance termination
- **Dry-run mode**: Test rotation logic without making actual changes
- **Detailed logging**: All decisions and actions are logged with full context
- **Telegram notifications**: Real-time alerts for all lifecycle events

### Integration with Existing Systems
- **Seamless integration**: Works with existing parallel execution engine
- **Limit-aware**: Builds upon Issue #64's limit detection capabilities
- **State management**: Maintains rotation statistics and history
- **Performance optimized**: Respects existing 93% performance improvements

## Configuration

### Environment Variables

```bash
# Instance Lifecycle Management
AUTO_ROTATE_INSTANCES="true"             # Enable automatic rotation (default: false)
INSTANCE_MIN_AGE_HOURS="24"              # Minimum age before rotation eligible (default: 24)
ROTATION_STRATEGY="oldest_first"         # Rotation strategy (default: oldest_first)
HEALTH_CHECK_ENABLED="true"              # Enable health checks (default: true)
DRY_RUN="false"                          # Dry run mode for testing (default: false)
```

### Rotation Strategies

#### `oldest_first` (Default)
- Selects instances with the longest uptime for termination
- Preserves recently created instances
- Best for maintaining fresh deployments

#### `least_utilized` 
- Considers instance health scores and utilization
- Selects instances with lowest health scores first
- Best for maintaining optimal resource usage

### Safety Configuration

```bash
# Minimum age protection (hours)
INSTANCE_MIN_AGE_HOURS="24"              # Default: 24 hours

# Health check behavior
HEALTH_CHECK_ENABLED="true"              # Verify instance state before rotation
```

## Usage Examples

### Basic Usage

```bash
# Enable auto-rotation for automatic capacity management
export AUTO_ROTATE_INSTANCES=true
./scripts/launch-parallel.sh
```

### Advanced Configuration

```bash
# Use least-utilized strategy with 48-hour minimum age
export AUTO_ROTATE_INSTANCES=true
export ROTATION_STRATEGY="least_utilized" 
export INSTANCE_MIN_AGE_HOURS=48
export HEALTH_CHECK_ENABLED=true

./scripts/launch-parallel.sh
```

### Testing and Validation

```bash
# Test rotation logic without making changes
./scripts/instance-lifecycle.sh dry-run

# View current lifecycle statistics
./scripts/instance-lifecycle.sh stats

# List all instances with details
./scripts/instance-lifecycle.sh list
```

### Manual Lifecycle Management

```bash
# Run lifecycle management independently
export AUTO_ROTATE_INSTANCES=true
./scripts/instance-lifecycle.sh manage

# Test with different strategies
ROTATION_STRATEGY="least_utilized" ./scripts/instance-lifecycle.sh dry-run
```

## How It Works

### Integration with Parallel Execution

1. **Limit Detection**: Parallel launcher checks cached limit states for both shapes
2. **Auto-rotation Trigger**: When both shapes hit limits and `AUTO_ROTATE_INSTANCES=true`
3. **Lifecycle Management**: Executes rotation to free capacity
4. **Instance Creation**: Proceeds with normal instance creation after rotation

### Rotation Process

1. **Shape Analysis**: Determines which shapes are at capacity limits
2. **Instance Selection**: Applies configured strategy to select instances for rotation
3. **Safety Validation**: Verifies instance age, health, and other safety criteria
4. **Termination**: Gracefully terminates selected instances
5. **Verification**: Confirms successful termination and updates state

### Safety Mechanisms

- **Minimum Age Enforcement**: Never rotates instances younger than configured minimum
- **Health Verification**: Checks instance state before termination
- **OCID Validation**: Ensures instance exists and is accessible
- **Dry Run Support**: Test all logic without making changes
- **Comprehensive Logging**: Full audit trail of all decisions and actions

## Monitoring and Notifications

### Telegram Notifications

The system sends notifications for:
- **Rotation Started**: When lifecycle management begins
- **Instance Terminated**: For each instance terminated
- **Rotation Completed**: Summary of rotation results
- **Errors and Warnings**: Any issues during lifecycle management

### Logging and Statistics

```bash
# View lifecycle statistics
./scripts/instance-lifecycle.sh stats

# Example output:
# Lifecycle Management Statistics:
#   Total rotations: 15
#   Last rotation: 2025-01-15T10:30:45.123Z
#   Recent activity:
#     2025-01-15T10:30:45.123Z: terminated a1-flex-instance-old (ocid1.instance...)
#     2025-01-14T08:15:22.456Z: terminated e2-micro-instance-old (ocid1.instance...)
```

## Shape-Specific Behavior

### A1.Flex (ARM) Instances
- **Limit Tracking**: Monitors total OCPU usage (4 OCPU limit)
- **Smart Selection**: Considers OCPU allocation in rotation decisions
- **Health Scoring**: Factors in resource utilization and performance

### E2.1.Micro (AMD) Instances  
- **Instance Counting**: Tracks total instance count (2 instance limit)
- **Simple Selection**: Age-based or health-based selection
- **Quick Rotation**: Faster termination due to smaller resource footprint

## Error Handling

The system handles various error conditions:

### Expected Scenarios
- **No Eligible Instances**: When all instances are too young
- **API Failures**: Graceful handling of OCI API errors
- **Permission Issues**: Clear error messages for insufficient permissions

### Recovery Strategies
- **Transient Errors**: Automatic retry with exponential backoff
- **Capacity Errors**: Continue normal capacity-aware behavior
- **Authentication Errors**: Clear alerts with troubleshooting guidance

## Performance Impact

### Optimization Features
- **Cached Limit States**: Avoids unnecessary API calls
- **Selective Execution**: Only runs when limits are detected
- **Parallel-Aware**: Integrates seamlessly with existing parallel execution
- **Efficient API Usage**: Minimizes OCI API calls through smart caching

### Performance Metrics
- **Typical Overhead**: <2 seconds when rotation is not needed
- **Rotation Time**: ~10-15 seconds for single instance rotation
- **API Efficiency**: Uses existing optimized OCI CLI wrapper

## Best Practices

### Production Usage

1. **Start with Dry Run**: Test thoroughly before enabling auto-rotation
2. **Conservative Timing**: Use longer minimum ages (48-72 hours) initially
3. **Monitor Closely**: Watch Telegram notifications and logs during initial rollout
4. **Gradual Rollout**: Enable for one shape first, then expand

### Configuration Recommendations

```bash
# Conservative production configuration
AUTO_ROTATE_INSTANCES="true"
INSTANCE_MIN_AGE_HOURS="48"           # 48 hour minimum age
ROTATION_STRATEGY="oldest_first"       # Predictable rotation
HEALTH_CHECK_ENABLED="true"            # Always verify health
```

### Monitoring Setup

```bash
# Enable structured logging for analysis
LOG_FORMAT="json"

# Ensure notifications are configured
ENABLE_NOTIFICATIONS="true"
TELEGRAM_TOKEN="your_bot_token"
TELEGRAM_USER_ID="your_user_id"
```

## Troubleshooting

### Common Issues

#### Auto-rotation Not Working
```bash
# Check configuration
./scripts/validate-config.sh

# Verify limits are actually reached
./scripts/instance-lifecycle.sh list

# Test with dry run
./scripts/instance-lifecycle.sh dry-run
```

#### Instances Not Being Selected
```bash
# Check minimum age requirements
echo "Current minimum age: $INSTANCE_MIN_AGE_HOURS hours"

# List instances with ages
./scripts/instance-lifecycle.sh list | jq '.[] | {name: .name, age_hours: ((now - (.created | fromdateiso8601)) / 3600 | floor)}'
```

#### Permission Errors
```bash
# Verify OCI credentials have termination permissions
oci iam user list-groups --user-id "$OCI_USER_OCID"

# Test OCI connectivity
oci compute instance list --compartment-id "$OCI_COMPARTMENT_ID" --limit 1
```

### Debug Mode

```bash
# Enable detailed logging
export DEBUG=true
export LOG_FORMAT=json

# Run with full verbosity
./scripts/instance-lifecycle.sh manage
```

## Testing

### Test Suite

```bash
# Run lifecycle management tests
./tests/test_instance_lifecycle.sh

# Expected output:
# [TEST] Starting instance lifecycle management tests...
# [TEST] ✅ PASS: AUTO_ROTATE_INSTANCES default
# [TEST] ✅ PASS: Age calculation for 2-hour-old instance
# ...
# [TEST] Test Summary:
# [TEST]   Tests run: 28
# [TEST]   Tests passed: 28
# [TEST]   Tests failed: 0
# [TEST] ✅ All tests passed!
```

### Manual Testing

```bash
# Test configuration validation
AUTO_ROTATE_INSTANCES="invalid" ./scripts/validate-config.sh

# Test age calculation with mock data
./scripts/instance-lifecycle.sh list

# Test dry run mode
DRY_RUN=true ./scripts/instance-lifecycle.sh manage
```

## Integration Examples

### GitHub Actions Workflow

```yaml
# Enable auto-rotation in workflow
env:
  AUTO_ROTATE_INSTANCES: 'true'
  INSTANCE_MIN_AGE_HOURS: '24'
  ROTATION_STRATEGY: 'oldest_first'
  HEALTH_CHECK_ENABLED: 'true'
```

### Cron-Based Automation

```bash
#!/bin/bash
# Daily lifecycle management
export AUTO_ROTATE_INSTANCES=true
export INSTANCE_MIN_AGE_HOURS=72
cd /path/to/OracleInstanceCreator
./scripts/instance-lifecycle.sh manage
```

## Security Considerations

### Permissions Required

The lifecycle management system requires OCI permissions for:
- `compute:instance:list` - List instances in compartment
- `compute:instance:read` - Get instance details for health checks  
- `compute:instance:terminate` - Terminate instances for rotation

### Audit Trail

- All termination actions are logged with full context
- Telegram notifications provide real-time audit trail
- Lifecycle statistics maintain historical record
- Debug logs capture detailed decision processes

### Safety Measures

- **Minimum Age Protection**: Prevents accidental termination of new instances
- **Health Verification**: Ensures instances are in valid states before termination
- **Dry Run Mode**: Allows testing without making changes
- **Explicit Opt-in**: Feature disabled by default
- **Multiple Confirmation**: Several validation steps before termination

This comprehensive lifecycle management system transforms the Oracle Instance Creator from intelligent limit detection to full autonomous instance management, providing a complete hands-off experience for Oracle Cloud free tier automation.