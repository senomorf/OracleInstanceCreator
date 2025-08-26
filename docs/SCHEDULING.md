# Oracle Instance Creator - Enhanced Scheduler Documentation

## Overview

The Enhanced Scheduler Optimization system provides intelligent, cost-effective automation for Oracle Cloud Infrastructure free tier instance creation. This document explains the three-tier scheduling approach, cost calculations, and troubleshooting procedures.

## 🎯 Key Achievements

- **81-85% Cost Reduction**: From 7,200 to 1,068-1,440 monthly workflow runs
- **Free Tier Compliance**: 53-72% usage vs 2,000-minute limit
- **Regional Intelligence**: Timezone-aware scheduling for optimal success rates
- **Adaptive Learning**: Pattern tracking for continuous optimization

## ⏰ Three-Tier Scheduling System

### 1. Off-Peak Aggressive Schedule
```yaml
cron: "*/15 2-7 * * *"
```
- **Frequency**: Every 15 minutes
- **UTC Hours**: 2:00-7:00 AM
- **Singapore Time**: 10:00 AM - 3:00 PM
- **Rationale**: Lunch hours and afternoon lull in business activity
- **Usage**: ~25 runs/weekday × 22 weekdays = 550 runs/month

### 2. Conservative Peak Schedule  
```yaml
cron: "0 8-23,0-1 * * *"
```
- **Frequency**: Every 60 minutes
- **UTC Hours**: 8:00-23:00 + 0:00-1:00 (17 hours total)
- **Singapore Time**: 4:00 PM - 9:00 AM (avoiding peak business)
- **Rationale**: Conservative approach during high-usage periods
- **Usage**: ~17 runs/weekday × 22 weekdays = 374 runs/month

### 3. Weekend Boost Schedule
```yaml
cron: "*/20 1-6 * * 6,0"
```
- **Frequency**: Every 20 minutes
- **UTC Hours**: 1:00-6:00 AM on Saturday and Sunday
- **Singapore Time**: 9:00 AM - 2:00 PM weekends
- **Rationale**: Lower cloud usage on weekends allows more frequent attempts
- **Usage**: ~18 runs/weekend × 8 weekends = 144 runs/month

## 📊 Cost Analysis

### Monthly Usage Calculation
```
Weekday Aggressive:  550 runs × 1.5 min avg =  825 minutes
Weekday Conservative: 374 runs × 1.5 min avg =  561 minutes  
Weekend Boost:       144 runs × 1.5 min avg =  216 minutes
────────────────────────────────────────────────────────────
Total:              1,068 runs              = 1,602 minutes
```

### Free Tier Compliance
- **Current Usage**: 1,602 minutes (80% of limit)
- **Free Tier Limit**: 2,000 minutes/month
- **Safety Buffer**: 398 minutes remaining
- **Previous Usage**: 7,200 minutes (360% over limit ❌)
- **New Usage**: 1,602 minutes (80% of limit ✅)

## 🌍 Regional Timezone Mappings

### Singapore (ap-singapore-1) - Default
- **Business Hours**: 9:00 AM - 6:00 PM SGT (UTC+8)
- **UTC Equivalent**: 1:00 AM - 10:00 AM UTC
- **Off-Peak Window**: 2:00-7:00 AM UTC = 10:00 AM-3:00 PM SGT

### US East (us-east-1, ca-central-1)
- **Business Hours**: 9:00 AM - 6:00 PM EST (UTC-5)
- **UTC Equivalent**: 2:00 PM - 11:00 PM UTC
- **Off-Peak Window**: 6:00-12:00 PM UTC = 1:00-7:00 AM EST

### Europe (eu-frankfurt-1, eu-amsterdam-1)
- **Business Hours**: 9:00 AM - 6:00 PM CET (UTC+1)
- **UTC Equivalent**: 8:00 AM - 5:00 PM UTC
- **Off-Peak Window**: 6:00 PM-12:00 AM UTC = 7:00 PM-1:00 AM CET

### Mumbai (ap-mumbai-1)
- **Business Hours**: 9:00 AM - 6:00 PM IST (UTC+5:30)
- **UTC Equivalent**: 3:30 AM - 12:30 PM UTC
- **Off-Peak Window**: 1:00-6:00 PM UTC = 6:30-11:30 PM IST

## 🧠 Adaptive Intelligence Features

### Pattern Tracking
- **Data Storage**: GitHub repository variables (SUCCESS_PATTERN_DATA)
- **Retention**: Rolling window of last 50 entries (~10KB)
- **Size Limit**: 64KB GitHub variable limit with 85% safety buffer
- **Tracking**: Execution time, success rate, availability domain performance

### Success Pattern Analysis
```json
{
  "context": "off_peak_aggressive",
  "timestamp": "2023-08-26T04:30:00.000Z", 
  "type": "attempt",
  "duration": 18,
  "success": true,
  "region": "ap-singapore-1"
}
```

### Auto-Stop Mechanism
- **Variable**: `INSTANCE_CREATED` (true/false)
- **Behavior**: Stops scheduled runs when instance successfully created
- **Reset**: Manual trigger via dashboard or workflow dispatch

## 🛠️ Configuration & Troubleshooting

### Environment Variables
```bash
# Core scheduling
OCI_REGION="ap-singapore-1"                    # Target region
SUCCESS_TRACKING_ENABLED="true"                # Enable pattern tracking

# Pattern analysis
MIN_PATTERN_DATA_POINTS="10"                   # Min data for analysis
PATTERN_WINDOW_DAYS="30"                       # Analysis window

# Timing optimization  
TRANSIENT_ERROR_MAX_RETRIES="3"                # Same-AD retries
TRANSIENT_ERROR_RETRY_DELAY="15"               # Seconds between retries
```

### Performance Targets
- **Execution Time**: 17-18 seconds (optimal)
- **Success Rate**: Track via pattern analysis
- **API Calls**: Optimized with `--no-retry --connection-timeout 5`

### Common Issues & Solutions

#### 1. Workflow Not Triggering
```bash
# Check if auto-stop is enabled
gh variable get INSTANCE_CREATED

# Reset if needed  
gh variable set INSTANCE_CREATED --body "false"
```

#### 2. Pattern Tracking Errors
```bash
# Check GitHub token permissions
gh auth status

# Verify variables permission
# Token needs: repo, actions (read), variables (write)
```

#### 3. High Failure Rates
```bash
# Check current schedule context
./scripts/adaptive-scheduler.sh --analyze

# Review AD success patterns
./scripts/schedule-optimizer.sh --validate-region
```

#### 4. Free Tier Limit Exceeded
```bash
# Review current month usage
gh run list --limit 100 --json createdAt,conclusion

# Adjust schedule if needed (reduce frequency)
```

## 📈 Monitoring & Analytics

### Dashboard Metrics
- **Instance Status**: Current creation status and timing
- **Usage Tracking**: Monthly GitHub Actions minutes consumption
- **Success Patterns**: Visual analysis of optimal timing windows
- **AD Performance**: Success rates per availability domain

### Key Performance Indicators
1. **Cost Efficiency**: Monthly minutes vs free tier limit
2. **Success Rate**: Instance creation success percentage  
3. **Response Time**: Average workflow execution duration
4. **Schedule Accuracy**: Actual vs planned execution times

### Alerts & Notifications
- **Telegram Integration**: Success/failure notifications
- **Dashboard Warnings**: Free tier usage approaching limits
- **Pattern Anomalies**: Unexpected success rate changes

## 🔧 Advanced Configuration

### Custom Regional Schedules
To add support for new regions, update `scripts/schedule-optimizer.sh`:

```bash
"your-region-1")
    echo "# Your region optimized schedule"
    echo "# Off-peak aggressive: [UTC hours] ([local time] - [description])"
    echo 'schedule_aggressive: "*/15 [hours] * * *"'
    echo 'schedule_conservative: "0 [hours] * * *"'
    echo 'schedule_weekend: "*/20 [hours] * * 6,0"'
    ;;
```

### Schedule Intensity Adjustment
Modify cron patterns in `.github/workflows/free-tier-creation.yml`:

- **More Conservative**: Increase intervals (`*/30` instead of `*/15`)
- **More Aggressive**: Decrease intervals (`*/10` instead of `*/15`)  
- **Different Regions**: Adjust UTC hour ranges per timezone

### Pattern Analysis Tuning
```bash
# Increase data retention (max ~25KB for 125 entries)
export MIN_PATTERN_DATA_POINTS="25"
export PATTERN_WINDOW_DAYS="60" 

# More sensitive to patterns
export SUCCESS_THRESHOLD="0.8"    # 80% success rate threshold
```

## 📝 Validation Checklist

Before deploying schedule changes:

- [ ] Verify timezone calculations are correct
- [ ] Test cron expressions with online validators
- [ ] Calculate monthly usage stays under 2,000 minutes
- [ ] Ensure no schedule overlaps create excessive runs
- [ ] Test pattern tracking data size limits
- [ ] Validate regional business hours assumptions
- [ ] Check auto-stop mechanism functionality

## 🚀 Deployment Workflow

1. **Test Changes Locally**:
   ```bash
   ./tests/test_scheduler.sh
   ./tests/test_dashboard.sh
   ```

2. **Validate Schedules**:
   ```bash
   ./scripts/schedule-optimizer.sh --validate-all
   ```

3. **Deploy to Branch**:
   ```bash
   git commit -m "Update scheduling optimization"
   git push origin enhanced-scheduler-dashboard
   ```

4. **Manual Test Run**:
   ```bash
   gh workflow run free-tier-creation.yml \
     --ref enhanced-scheduler-dashboard \
     --field verbose_output=true
   ```

5. **Monitor Results**:
   - Check execution time (target: 17-18s)
   - Verify no errors in logs
   - Confirm dashboard updates correctly
   - Validate pattern tracking works

## 📚 References

- [GitHub Actions Cron Syntax](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#schedule)
- [Oracle Cloud Free Tier Limits](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)
- [GitHub Actions Usage Limits](https://docs.github.com/en/actions/learn-github-actions/usage-limits-billing-and-administration)
- [Oracle Cloud Regional Availability](https://docs.oracle.com/en-us/iaas/Content/General/Concepts/regions.htm)

---

*Last Updated: August 26, 2023*  
*Version: v2.0 Enhanced Scheduler*