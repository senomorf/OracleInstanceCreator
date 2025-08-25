// Oracle Instance Creator Dashboard JavaScript
class OracleInstanceDashboard {
    constructor() {
        this.config = {
            owner: '',
            repo: '',
            token: '',
            autoRefresh: true,
            refreshInterval: 30000
        };
        
        this.charts = {};
        this.refreshTimer = null;
        this.lastUpdate = null;
        
        this.init();
    }

    async init() {
        console.log('🚀 Initializing Oracle Instance Creator Dashboard...');
        
        // Load saved config
        this.loadConfig();
        
        // Initialize UI
        this.initializeUI();
        
        // Setup event listeners
        this.setupEventListeners();
        
        // Load initial data
        await this.refreshData();
        
        // Start auto-refresh if enabled
        if (this.config.autoRefresh) {
            this.startAutoRefresh();
        }
        
        console.log('✅ Dashboard initialized successfully');
    }

    loadConfig() {
        const saved = localStorage.getItem('oic-dashboard-config');
        if (saved) {
            this.config = { ...this.config, ...JSON.parse(saved) };
        }
        
        // Auto-detect from URL if possible
        if (!this.config.owner || !this.config.repo) {
            this.autoDetectRepo();
        }
    }

    saveConfig() {
        localStorage.setItem('oic-dashboard-config', JSON.stringify(this.config));
    }

    autoDetectRepo() {
        // Try to detect from GitHub Pages URL
        const hostname = window.location.hostname;
        if (hostname.includes('github.io')) {
            const parts = hostname.split('.');
            if (parts.length >= 2) {
                this.config.owner = parts[0];
                // Try to detect repo from pathname
                const path = window.location.pathname;
                const pathParts = path.split('/').filter(p => p);
                if (pathParts.length > 0) {
                    this.config.repo = pathParts[0];
                }
            }
        }
    }

    initializeUI() {
        // Initialize charts
        this.initCharts();
        
        // Update connection status
        this.updateConnectionStatus();
        
        // Show current config in UI
        this.updateConfigUI();
    }

    initCharts() {
        // Success Pattern Chart
        const successCtx = document.getElementById('success-pattern-chart');
        this.charts.successPattern = new Chart(successCtx, {
            type: 'line',
            data: {
                labels: [],
                datasets: [{
                    label: 'Success Rate %',
                    data: [],
                    borderColor: '#10b981',
                    backgroundColor: 'rgba(16, 185, 129, 0.1)',
                    borderWidth: 2,
                    fill: true,
                    tension: 0.4
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    y: {
                        beginAtZero: true,
                        max: 100,
                        ticks: {
                            callback: function(value) {
                                return value + '%';
                            }
                        }
                    }
                },
                plugins: {
                    legend: {
                        display: false
                    }
                }
            }
        });

        // Usage Chart
        const usageCtx = document.getElementById('usage-chart');
        this.charts.usage = new Chart(usageCtx, {
            type: 'doughnut',
            data: {
                labels: ['Used', 'Remaining'],
                datasets: [{
                    data: [0, 2000],
                    backgroundColor: ['#f59e0b', '#e5e7eb'],
                    borderWidth: 0
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: {
                        position: 'bottom'
                    }
                }
            }
        });
    }

    setupEventListeners() {
        // Settings button
        document.getElementById('settings-btn').addEventListener('click', () => {
            this.openModal('settings-modal');
        });

        // Close modal
        document.querySelector('.close').addEventListener('click', () => {
            this.closeModal();
        });

        // Save settings
        document.getElementById('save-settings').addEventListener('click', () => {
            this.saveSettings();
        });

        // Control buttons
        document.getElementById('trigger-workflow').addEventListener('click', () => {
            this.triggerWorkflow();
        });

        document.getElementById('reset-success').addEventListener('click', () => {
            this.resetSuccessState();
        });

        document.getElementById('export-data').addEventListener('click', () => {
            this.exportData();
        });

        document.getElementById('view-logs').addEventListener('click', () => {
            this.viewLogs();
        });

        // Refresh button
        document.getElementById('refresh-runs').addEventListener('click', () => {
            this.refreshData();
        });

        // Chart controls
        document.getElementById('pattern-timeframe').addEventListener('change', (e) => {
            this.updateSuccessPatternChart(parseInt(e.target.value));
        });

        document.getElementById('usage-view').addEventListener('change', (e) => {
            this.updateUsageChart(e.target.value);
        });

        // Region selector
        document.getElementById('region-selector').addEventListener('change', (e) => {
            this.updateRegionalAnalysis(e.target.value);
        });

        // Modal close on outside click
        window.addEventListener('click', (e) => {
            if (e.target.classList.contains('modal')) {
                this.closeModal();
            }
        });
    }

    async refreshData() {
        console.log('🔄 Refreshing dashboard data...');
        
        try {
            // Update last update time
            this.lastUpdate = new Date();
            document.getElementById('last-update').innerHTML = `
                <i class="far fa-clock"></i>
                <span>${this.formatTime(this.lastUpdate)}</span>
            `;

            // Fetch all data in parallel
            await Promise.all([
                this.updateInstanceStatus(),
                this.updateWorkflowRuns(),
                this.updateSuccessMetrics(),
                this.updateUsageMetrics(),
                this.updateADPerformance(),
                this.updateScheduleInfo()
            ]);

        } catch (error) {
            console.error('Error refreshing data:', error);
            this.showError('Failed to refresh data: ' + error.message);
        }
    }

    async updateInstanceStatus() {
        try {
            // Get repository variables to check instance status
            const variables = await this.githubAPI('/repos/' + this.config.owner + '/' + this.config.repo + '/actions/variables');
            
            const instanceCreated = variables.variables?.find(v => v.name === 'INSTANCE_CREATED');
            const instanceInfo = variables.variables?.find(v => v.name === 'INSTANCE_CREATED_INFO');
            
            let status = 'No Instance';
            let trend = 'Checking availability...';
            
            if (instanceCreated && instanceCreated.value === 'true') {
                status = 'Instance Active';
                trend = '✅ Instance successfully created';
                
                if (instanceInfo) {
                    try {
                        const info = JSON.parse(instanceInfo.value);
                        trend = `✅ Created in ${info.ad} at ${this.formatTime(new Date(info.timestamp))}`;
                    } catch (e) {
                        // Use default trend
                    }
                }
            } else {
                trend = '🔍 Actively searching for capacity...';
            }
            
            document.getElementById('instance-status').textContent = status;
            document.getElementById('instance-trend').textContent = trend;
            
        } catch (error) {
            document.getElementById('instance-status').textContent = 'Unknown';
            document.getElementById('instance-trend').textContent = 'Error fetching status';
        }
    }

    async updateWorkflowRuns() {
        try {
            const runs = await this.githubAPI(`/repos/${this.config.owner}/${this.config.repo}/actions/runs?per_page=10`);
            
            const container = document.getElementById('workflow-runs');
            
            if (!runs.workflow_runs || runs.workflow_runs.length === 0) {
                container.innerHTML = '<div class="loading">No workflow runs found</div>';
                return;
            }
            
            container.innerHTML = runs.workflow_runs.map(run => {
                const status = this.getRunStatus(run);
                const duration = this.calculateDuration(run.created_at, run.updated_at);
                
                return `
                    <div class="run-item">
                        <div class="run-status">
                            <div class="status-dot ${status.class}"></div>
                            <span>${status.text}</span>
                            <span class="run-time">${this.formatTime(new Date(run.created_at))}</span>
                        </div>
                        <div class="run-details">
                            <span class="run-duration">${duration}s</span>
                        </div>
                    </div>
                `;
            }).join('');
            
        } catch (error) {
            document.getElementById('workflow-runs').innerHTML = 
                '<div class="loading">Error loading workflow runs</div>';
        }
    }

    async updateSuccessMetrics() {
        try {
            // Get pattern data from repository variables
            const variables = await this.githubAPI(`/repos/${this.config.owner}/${this.config.repo}/actions/variables`);
            const patternData = variables.variables?.find(v => v.name === 'SUCCESS_PATTERN_DATA');
            
            let successRate = 0;
            let trend = 'No data available';
            
            if (patternData) {
                try {
                    const patterns = JSON.parse(patternData.value);
                    const totalAttempts = patterns.length;
                    const successes = patterns.filter(p => p.type === 'success').length;
                    
                    if (totalAttempts > 0) {
                        successRate = Math.round((successes / totalAttempts) * 100);
                        trend = `${successes}/${totalAttempts} attempts successful`;
                    }
                } catch (e) {
                    console.error('Error parsing pattern data:', e);
                }
            }
            
            document.getElementById('success-rate').textContent = `${successRate}%`;
            document.getElementById('success-trend').textContent = trend;
            
            // Update success pattern chart
            this.updateSuccessPatternChart(30, patternData ? JSON.parse(patternData.value) : []);
            
        } catch (error) {
            document.getElementById('success-rate').textContent = '---%';
            document.getElementById('success-trend').textContent = 'Error loading metrics';
        }
    }

    async updateUsageMetrics() {
        try {
            // Calculate estimated usage based on current schedule
            const now = new Date();
            const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
            const daysInMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
            const currentDay = now.getDate();
            
            // Estimated runs per day: ~45 (based on our enhanced schedule)
            const estimatedDailyRuns = 45;
            const estimatedMonthlyRuns = estimatedDailyRuns * daysInMonth;
            const currentMonthRuns = estimatedDailyRuns * currentDay;
            
            // Each run bills as 1 minute minimum
            const estimatedMonthlyMinutes = estimatedMonthlyRuns;
            const currentMonthMinutes = currentMonthRuns;
            
            const usagePercentage = Math.round((currentMonthMinutes / 2000) * 100);
            const remainingMinutes = 2000 - currentMonthMinutes;
            
            document.getElementById('usage-percentage').textContent = `${usagePercentage}%`;
            document.getElementById('usage-trend').textContent = 
                `${currentMonthMinutes}/${estimatedMonthlyMinutes} min projected`;
            
            // Update usage chart
            this.charts.usage.data.datasets[0].data = [currentMonthMinutes, Math.max(0, remainingMinutes)];
            this.charts.usage.data.datasets[0].backgroundColor = [
                usagePercentage > 80 ? '#ef4444' : usagePercentage > 60 ? '#f59e0b' : '#10b981',
                '#e5e7eb'
            ];
            this.charts.usage.update();
            
        } catch (error) {
            document.getElementById('usage-percentage').textContent = '---%';
            document.getElementById('usage-trend').textContent = 'Error calculating usage';
        }
    }

    async updateADPerformance() {
        try {
            const variables = await this.githubAPI(`/repos/${this.config.owner}/${this.config.repo}/actions/variables`);
            const patternData = variables.variables?.find(v => v.name === 'SUCCESS_PATTERN_DATA');
            
            const container = document.getElementById('ad-stats');
            
            if (!patternData) {
                container.innerHTML = '<div class="loading">No AD performance data available</div>';
                return;
            }
            
            const patterns = JSON.parse(patternData.value);
            const adStats = {};
            
            patterns.forEach(pattern => {
                if (pattern.ad && pattern.ad !== 'VERIFIED') {
                    if (!adStats[pattern.ad]) {
                        adStats[pattern.ad] = { total: 0, success: 0 };
                    }
                    adStats[pattern.ad].total++;
                    if (pattern.type === 'success') {
                        adStats[pattern.ad].success++;
                    }
                }
            });
            
            const adItems = Object.entries(adStats).map(([ad, stats]) => {
                const successRate = stats.total > 0 ? Math.round((stats.success / stats.total) * 100) : 0;
                return `
                    <div class="ad-item">
                        <div class="ad-name">${ad.split(':')[1] || ad}</div>
                        <div class="ad-stats">
                            <div class="ad-stat">${successRate}% success</div>
                            <div class="ad-stat">${stats.total} attempts</div>
                        </div>
                    </div>
                `;
            }).join('');
            
            container.innerHTML = adItems || '<div class="loading">No AD data available</div>';
            document.getElementById('ad-update-time').textContent = `Updated: ${this.formatTime(new Date())}`;
            
        } catch (error) {
            document.getElementById('ad-stats').innerHTML = '<div class="loading">Error loading AD stats</div>';
        }
    }

    async updateScheduleInfo() {
        try {
            // Calculate next run time based on cron schedules
            const nextRun = this.calculateNextRun();
            document.getElementById('next-run').textContent = this.formatTime(nextRun);
            
            // Determine current schedule context
            const context = this.getCurrentScheduleContext();
            document.getElementById('schedule-context').textContent = context;
            
        } catch (error) {
            document.getElementById('next-run').textContent = '--:--';
            document.getElementById('schedule-context').textContent = 'Error calculating schedule';
        }
    }

    updateSuccessPatternChart(days, data = null) {
        if (!data) {
            // Mock data for demonstration
            const labels = [];
            const successData = [];
            
            for (let i = days - 1; i >= 0; i--) {
                const date = new Date();
                date.setDate(date.getDate() - i);
                labels.push(date.toLocaleDateString());
                successData.push(Math.random() * 100);
            }
            
            this.charts.successPattern.data.labels = labels;
            this.charts.successPattern.data.datasets[0].data = successData;
        } else {
            // Process real data
            const dailyStats = {};
            const cutoffDate = new Date();
            cutoffDate.setDate(cutoffDate.getDate() - days);
            
            data.forEach(pattern => {
                const date = new Date(pattern.timestamp).toDateString();
                if (new Date(pattern.timestamp) >= cutoffDate) {
                    if (!dailyStats[date]) {
                        dailyStats[date] = { total: 0, success: 0 };
                    }
                    dailyStats[date].total++;
                    if (pattern.type === 'success') {
                        dailyStats[date].success++;
                    }
                }
            });
            
            const labels = [];
            const successData = [];
            
            for (let i = days - 1; i >= 0; i--) {
                const date = new Date();
                date.setDate(date.getDate() - i);
                const dateStr = date.toDateString();
                
                labels.push(date.toLocaleDateString());
                
                const stats = dailyStats[dateStr];
                if (stats && stats.total > 0) {
                    successData.push(Math.round((stats.success / stats.total) * 100));
                } else {
                    successData.push(0);
                }
            }
            
            this.charts.successPattern.data.labels = labels;
            this.charts.successPattern.data.datasets[0].data = successData;
        }
        
        this.charts.successPattern.update();
    }

    async updateRegionalAnalysis(region = 'auto') {
        const container = document.getElementById('schedule-recommendations');
        
        // Regional schedule recommendations
        const recommendations = this.getRegionalRecommendations(region);
        
        container.innerHTML = recommendations.map(rec => `
            <div class="schedule-card">
                <div class="schedule-title">${rec.title}</div>
                <div class="schedule-details">${rec.description}</div>
                <div class="schedule-metrics">
                    <div class="metric">Cron: ${rec.cron}</div>
                    <div class="metric">${rec.frequency}</div>
                    <div class="metric">${rec.usage}</div>
                </div>
            </div>
        `).join('');
    }

    getRegionalRecommendations(region) {
        const recommendations = {
            'ap-singapore-1': [
                {
                    title: 'Off-Peak Aggressive',
                    description: '2-7am UTC (10am-3pm SGT) - Lunch/low activity hours',
                    cron: '*/15 2-7 * * *',
                    frequency: '24 runs/day',
                    usage: '720 min/month'
                },
                {
                    title: 'Peak Conservative', 
                    description: '8am-1am UTC (4pm-9am SGT) - Avoid business peak',
                    cron: '0 8-23,0-1 * * *',
                    frequency: '18 runs/day',
                    usage: '540 min/month'
                },
                {
                    title: 'Weekend Boost',
                    description: '1-6am UTC weekends (9am-2pm SGT) - Lower weekend demand',
                    cron: '*/20 1-6 * * 6,0',
                    frequency: '18 runs/weekend',
                    usage: '144 min/month'
                }
            ],
            'us-east-1': [
                {
                    title: 'Night Hours Aggressive',
                    description: '6-12 UTC (1am-7am EST) - Deep night hours',
                    cron: '*/15 6-12 * * *',
                    frequency: '24 runs/day',
                    usage: '720 min/month'
                },
                {
                    title: 'Business Hours Conservative',
                    description: '13-5 UTC (8am-12am EST) - Avoid business/evening',
                    cron: '0 13-23,0-5 * * *',
                    frequency: '17 runs/day', 
                    usage: '510 min/month'
                }
            ],
            'eu-frankfurt-1': [
                {
                    title: 'Evening Low Activity',
                    description: '18-23 UTC (7pm-12am CET) - Evening low usage',
                    cron: '*/15 18-23 * * *',
                    frequency: '24 runs/day',
                    usage: '720 min/month'
                },
                {
                    title: 'Non-Business Hours',
                    description: '0-8,17 UTC (1am-9am,6pm CET) - Outside business',
                    cron: '0 0-8,17 * * *',
                    frequency: '9 runs/day',
                    usage: '270 min/month'
                }
            ]
        };
        
        return recommendations[region] || recommendations['ap-singapore-1'];
    }

    calculateNextRun() {
        // Simplified calculation for next cron run
        // In a real implementation, you'd parse the actual cron expressions
        const now = new Date();
        const nextRun = new Date(now);
        
        // Find next 15-minute interval for aggressive schedule (2-7am UTC)
        const hour = now.getUTCHours();
        const minute = now.getUTCMinutes();
        
        if (hour >= 2 && hour < 7) {
            // In aggressive window - next 15-minute mark
            const nextMinute = Math.ceil(minute / 15) * 15;
            if (nextMinute >= 60) {
                nextRun.setUTCHours(hour + 1, 0, 0, 0);
            } else {
                nextRun.setUTCMinutes(nextMinute, 0, 0);
            }
        } else {
            // In conservative window - next hour
            nextRun.setUTCHours(hour + 1, 0, 0, 0);
        }
        
        return nextRun;
    }

    getCurrentScheduleContext() {
        const hour = new Date().getUTCHours();
        const day = new Date().getUTCDay();
        
        if (hour >= 2 && hour < 7) {
            return 'Off-peak aggressive (SGT lunch hours)';
        } else if ((day === 0 || day === 6) && hour >= 1 && hour < 6) {
            return 'Weekend boost period';
        } else {
            return 'Conservative peak hours';
        }
    }

    async githubAPI(endpoint, options = {}) {
        if (!this.config.token) {
            throw new Error('GitHub token not configured');
        }
        
        const url = `https://api.github.com${endpoint}`;
        const response = await fetch(url, {
            headers: {
                'Authorization': `Bearer ${this.config.token}`,
                'Accept': 'application/vnd.github.v3+json',
                ...options.headers
            },
            ...options
        });
        
        if (!response.ok) {
            throw new Error(`GitHub API error: ${response.status} ${response.statusText}`);
        }
        
        return response.json();
    }

    getRunStatus(run) {
        switch (run.status) {
            case 'completed':
                if (run.conclusion === 'success') {
                    return { class: 'success', text: 'Success' };
                } else {
                    return { class: 'error', text: 'Failed' };
                }
            case 'in_progress':
                return { class: 'running', text: 'Running' };
            default:
                return { class: 'error', text: run.status };
        }
    }

    calculateDuration(start, end) {
        const startTime = new Date(start);
        const endTime = new Date(end);
        return Math.round((endTime - startTime) / 1000);
    }

    formatTime(date) {
        return date.toLocaleTimeString([], { 
            hour: '2-digit', 
            minute: '2-digit',
            hour12: false
        });
    }

    openModal(modalId) {
        document.getElementById(modalId).style.display = 'block';
    }

    closeModal() {
        document.querySelectorAll('.modal').forEach(modal => {
            modal.style.display = 'none';
        });
    }

    saveSettings() {
        this.config.token = document.getElementById('github-token').value;
        this.config.owner = document.getElementById('repo-owner').value;
        this.config.repo = document.getElementById('repo-name').value;
        this.config.autoRefresh = document.getElementById('auto-refresh').checked;
        
        this.saveConfig();
        this.updateConnectionStatus();
        this.closeModal();
        
        // Refresh data with new settings
        this.refreshData();
    }

    updateConnectionStatus() {
        const statusEl = document.getElementById('connection-status');
        
        if (this.config.token && this.config.owner && this.config.repo) {
            statusEl.innerHTML = '<i class="fas fa-circle" style="color: #10b981;"></i><span>Connected</span>';
        } else {
            statusEl.innerHTML = '<i class="fas fa-circle" style="color: #ef4444;"></i><span>Not Configured</span>';
        }
    }

    updateConfigUI() {
        if (this.config.token) {
            document.getElementById('github-token').value = this.config.token;
        }
        if (this.config.owner) {
            document.getElementById('repo-owner').value = this.config.owner;
        }
        if (this.config.repo) {
            document.getElementById('repo-name').value = this.config.repo;
        }
        document.getElementById('auto-refresh').checked = this.config.autoRefresh;
    }

    startAutoRefresh() {
        if (this.refreshTimer) {
            clearInterval(this.refreshTimer);
        }
        
        this.refreshTimer = setInterval(() => {
            this.refreshData();
        }, this.refreshInterval);
    }

    async triggerWorkflow() {
        try {
            await this.githubAPI(`/repos/${this.config.owner}/${this.config.repo}/actions/workflows/free-tier-creation.yml/dispatches`, {
                method: 'POST',
                body: JSON.stringify({
                    ref: 'main'
                })
            });
            
            this.showSuccess('Workflow triggered successfully');
            setTimeout(() => this.refreshData(), 5000);
        } catch (error) {
            this.showError('Failed to trigger workflow: ' + error.message);
        }
    }

    async resetSuccessState() {
        try {
            await this.githubAPI(`/repos/${this.config.owner}/${this.config.repo}/actions/workflows/free-tier-creation.yml/dispatches`, {
                method: 'POST',
                body: JSON.stringify({
                    ref: 'main',
                    inputs: {
                        reset_success_state: 'true'
                    }
                })
            });
            
            this.showSuccess('Success state reset workflow triggered');
            setTimeout(() => this.refreshData(), 5000);
        } catch (error) {
            this.showError('Failed to reset success state: ' + error.message);
        }
    }

    exportData() {
        const data = {
            timestamp: new Date().toISOString(),
            config: { ...this.config, token: '[REDACTED]' },
            lastUpdate: this.lastUpdate
        };
        
        const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `oracle-instance-dashboard-${Date.now()}.json`;
        a.click();
        URL.revokeObjectURL(url);
        
        this.showSuccess('Dashboard data exported');
    }

    viewLogs() {
        const url = `https://github.com/${this.config.owner}/${this.config.repo}/actions`;
        window.open(url, '_blank');
    }

    showSuccess(message) {
        this.showNotification(message, 'success');
    }

    showError(message) {
        this.showNotification(message, 'error');
    }

    showNotification(message, type) {
        // Simple notification system
        const notification = document.createElement('div');
        notification.className = `notification ${type}`;
        notification.textContent = message;
        notification.style.cssText = `
            position: fixed;
            top: 20px;
            right: 20px;
            padding: 12px 20px;
            border-radius: 6px;
            color: white;
            background: ${type === 'success' ? '#10b981' : '#ef4444'};
            z-index: 1000;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
        `;
        
        document.body.appendChild(notification);
        
        setTimeout(() => {
            notification.remove();
        }, 5000);
    }
}

// Initialize dashboard when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    new OracleInstanceDashboard();
});