# Oracle Instance Creator Dashboard

A comprehensive real-time monitoring and analytics dashboard for the Oracle Cloud Infrastructure free tier instance creation workflow.

## 📊 Features

### Real-Time Monitoring
- **Instance Status**: Current state and creation history
- **Success Rate Analytics**: Pattern analysis over 7/30/90 day periods  
- **Free Tier Usage**: Monthly GitHub Actions minutes tracking
- **Next Run Prediction**: Smart scheduling with context awareness

### Advanced Analytics
- **Success Pattern Visualization**: Interactive charts showing optimal creation times
- **Availability Domain Performance**: Success rates by Oracle AD
- **Regional Optimization**: Timezone-aware scheduling recommendations
- **Workflow Run History**: Complete execution logs with timing data

### Interactive Controls
- **Manual Workflow Triggers**: Start instance creation on-demand
- **Success State Reset**: Clear success flags to resume attempts
- **Data Export**: Download analytics for external analysis
- **Real-Time Refresh**: Auto-updating dashboard every 30 seconds

## 🚀 Quick Start

### 1. Enable GitHub Pages

1. Go to your repository **Settings** → **Pages**
2. Set **Source** to "Deploy from a branch"
3. Select **Branch**: `main` or `master` 
4. Set **Folder** to `/docs`
5. Click **Save**

### 2. Access Dashboard

Your dashboard will be available at:
```
https://[username].github.io/[repository-name]/dashboard/
```

### 3. Configure Access

1. Click the **Settings** button (⚙️) in the bottom right
2. Enter your GitHub Personal Access Token
3. Set Repository Owner and Name
4. Enable auto-refresh if desired
5. Click **Save Settings**

### 4. Create Personal Access Token

1. Go to GitHub **Settings** → **Developer settings** → **Personal access tokens**
2. Click **Generate new token (classic)**
3. Select these scopes:
   - `repo` (Full control of private repositories)
   - `workflow` (Update GitHub Action workflows)
   - `actions:read` (Read access to Actions)
4. Copy the token to the dashboard settings

## 📱 Dashboard Sections

### Statistics Overview
- **Instance Status**: Shows if an instance is currently active
- **Success Rate**: Historical success percentage with trends
- **Free Tier Usage**: Current month's GitHub Actions minutes consumption  
- **Next Scheduled Run**: Countdown to next automated attempt

### Success Pattern Analysis
Interactive chart showing:
- Success rates by hour of day (UTC)
- Weekly patterns and optimal windows
- 7/30/90-day trend analysis
- Regional optimization insights

### Usage Tracking
Visual representation of:
- Monthly minutes consumption vs 2,000 free tier limit
- Daily usage patterns
- Projected monthly usage
- Buffer remaining for manual runs

### Workflow Run History
Recent execution log showing:
- Run status (Success/Failed/Running)
- Execution duration
- Start time and context
- Error details for failed runs

### AD Performance Metrics
Availability Domain statistics:
- Success rate per AD
- Total attempts per AD
- Performance recommendations
- Historical effectiveness data

### Regional Schedule Optimization
Intelligent scheduling recommendations:
- Current region detection
- Optimal time windows for different Oracle regions
- Cron expression suggestions
- Usage impact estimates

### Workflow Controls
Direct interaction capabilities:
- **Trigger Manual Run**: Start instance creation immediately
- **Reset Success State**: Clear success flags to resume automation
- **Export Analytics**: Download complete dashboard data
- **View Logs**: Open GitHub Actions execution logs

## 🔧 Technical Architecture

### Frontend Stack
- **HTML5**: Semantic, accessible structure
- **CSS3**: Modern responsive design with CSS Grid/Flexbox
- **Vanilla JavaScript**: No framework dependencies
- **Chart.js**: Interactive data visualization
- **Font Awesome**: Professional iconography

### Data Sources
- **GitHub Actions API**: Workflow run history and status
- **Repository Variables**: Success patterns and configuration
- **Real-time Calculations**: Usage estimates and predictions

### Security
- **Client-side Only**: No server-side components or data storage
- **Token Encryption**: Personal access tokens stored locally only
- **HTTPS**: All API calls use secure connections
- **Minimal Permissions**: Only required GitHub scopes requested

## 📈 Usage Analytics

### Success Pattern Tracking
The dashboard collects and analyzes:
- Success/failure timestamps by UTC hour
- Availability domain performance
- Day-of-week patterns
- Monthly success trends

### Cost Optimization
Automated monitoring of:
- GitHub Actions minutes consumption
- Free tier compliance (2,000 min/month)
- Projected monthly usage
- Buffer calculations for manual runs

### Regional Intelligence
Smart recommendations based on:
- Oracle Cloud region business hours
- Timezone-aware optimal windows
- Regional capacity patterns
- Multi-schedule coordination

## 🛠️ Customization

### Styling
Customize appearance by editing:
- `/docs/dashboard/css/dashboard.css`
- CSS custom properties (variables) at top of file
- Color scheme, typography, spacing

### Functionality
Extend features by modifying:
- `/docs/dashboard/js/dashboard.js`
- Add new chart types or data sources
- Implement additional API integrations
- Create custom analytics

### Configuration
Dashboard behavior controlled by:
- Local browser storage for user settings
- URL parameters for sharing configurations
- Environment detection for auto-setup

## 🎨 Screenshots

*Dashboard screenshots would be displayed here after deployment*

## 📚 Integration

### With Oracle Instance Creator
The dashboard seamlessly integrates with:
- Enhanced workflow scheduler
- Adaptive scheduling intelligence  
- Success pattern tracking
- Regional optimization features

### GitHub Actions
Monitors and controls:
- Free tier instance creation workflow
- Manual workflow dispatches
- Success state management
- Usage tracking and reporting

## 🔒 Privacy & Security

### Data Handling
- **No External Servers**: Dashboard runs entirely in browser
- **Local Storage Only**: Settings saved in browser localStorage
- **No Data Collection**: No analytics or tracking of user behavior
- **Token Security**: GitHub tokens never transmitted to third parties

### Permissions Required
Minimal GitHub permissions needed:
- **Repository Read**: View workflow runs and variables
- **Actions Write**: Trigger workflows and manage variables
- **Metadata Read**: Access basic repository information

## 🚨 Troubleshooting

### Common Issues

**Dashboard shows "Not Configured"**
- Verify GitHub Personal Access Token is set
- Check repository owner/name are correct
- Ensure token has required permissions

**"Error loading data" messages**
- Check token hasn't expired
- Verify repository is accessible
- Check browser console for detailed errors

**Charts not displaying**
- Ensure internet connection for Chart.js CDN
- Check browser compatibility (modern browsers required)
- Verify JavaScript is enabled

**Workflow controls not working**
- Confirm token has `workflow` scope
- Check repository has the correct workflow file
- Verify branch name (main vs master)

### Support

For issues or feature requests:
1. Check existing GitHub Issues
2. Create new issue with detailed description
3. Include browser console logs if applicable
4. Specify dashboard version and browser type

## 📄 License

This dashboard is part of the Oracle Instance Creator project and follows the same open-source license terms.