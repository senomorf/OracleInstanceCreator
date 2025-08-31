# Free Tier Limits Management

Error-driven limit detection prevents 4,320+ monthly futile API calls via 24h cache.

## Commands

```bash
# Check limit status
./scripts/state-manager.sh limit-status

# Check specific shape
./scripts/state-manager.sh check-limit "VM.Standard.E2.1.Micro"

# Clear all cached limits  
./scripts/state-manager.sh clear-limits

# Manual limit override
./scripts/state-manager.sh set-limit "VM.Standard.A1.Flex" false
```

## Free Tier Limits
- **E2.1.Micro**: 2 instances max
- **A1.Flex**: 4 OCPUs total, 24GB total

## Behavior
- Exit code 5: USER_LIMIT_REACHED (cached 24h)
- Exit code 2: ORACLE_CAPACITY_UNAVAILABLE (retry)
- Pre-flight cache check skips shapes at known limits