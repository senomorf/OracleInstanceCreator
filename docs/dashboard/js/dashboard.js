/* global Chart, dateFns */
// OCI Orchestrator Dashboard JavaScript
class OracleInstanceDashboard {
  constructor() {
    // Constants for better maintainability
    this.CONSTANTS = {
      // Timing constants (in milliseconds)
      DEFAULT_REFRESH_INTERVAL: 120000, // 2 minutes refresh
      DEFAULT_BASE_DELAY: 800, // Base delay between API calls
      EXPONENTIAL_BASE_DELAY: 1000, // 1 second base for exponential backoff
      EXPONENTIAL_MAX_DELAY: 30000, // 30 seconds max exponential delay
      CDN_RETRY_BASE_DELAY: 1000, // CDN check retry base delay
      AUTH_CALLS_INITIAL_DELAY: 1000, // Delay before authenticated calls
      FIRST_TIME_SETUP_DELAY: 1000, // Delay for showing setup modal

      // Rate limiting thresholds
      RATE_LIMIT_DEFAULT_REMAINING: 5000, // Default when unknown
      RATE_LIMIT_CRITICAL_THRESHOLD: 10, // Critical threshold
      RATE_LIMIT_LOW_THRESHOLD: 50, // Low threshold
      RATE_LIMIT_WARNING_THRESHOLD: 100, // Warning threshold
      RATE_LIMIT_APPROACHING_THRESHOLD: 200, // Approaching limits threshold
      RATE_LIMIT_WARNING_RESET_MINUTES: 30, // Minutes for warning reset logic
      RATE_LIMIT_WARNING_RESET_REMAINING: 500, // Requests for warning reset logic

      // Cache and offline constants
      CACHE_VALIDITY_HOURS: 24, // Cache valid for 24 hours
      OFFLINE_CACHE_SIZE_LIMIT: 50000, // 50KB cache limit

      // Time conversion constants
      MS_PER_MINUTE: 60000, // Milliseconds per minute
      MS_PER_HOUR: 3600000, // Milliseconds per hour
      SECONDS_PER_MINUTE: 60, // Seconds per minute

      // API and UI constants
      DEFAULT_MAX_RETRIES: 3, // Default retry attempts
      PERCENTAGE_MULTIPLIER: 100, // For percentage calculations
      JITTER_FACTOR: 0.1, // Jitter percentage (10%)
    };

    this.config = {
      owner: "",
      repo: "",
      token: "",
      autoRefresh: true,
      refreshInterval: this.CONSTANTS.DEFAULT_REFRESH_INTERVAL,
    };

    this.charts = {};
    this.refreshTimer = null;
    this.offlineTimer = null;
    this.refreshInProgress = false;
    this.lastUpdate = null;
    this.cdnFallbacks = {
      chartjs: false,
      dateFns: false,
      fontAwesome: false,
    };
    this.offlineMode = {
      enabled: false,
      lastDataCache: null,
      cacheTimestamp: null,
    };
    this.rateLimitState = {
      exceeded: false,
      resetTime: null,
      remaining: null,
      retryAfter: null,
      warningShown: false,
      retryCount: 0,
      maxRetries: 3,
      baseDelay: this.CONSTANTS.EXPONENTIAL_BASE_DELAY, // 1 second base delay
    };

    // Cache frequently accessed DOM elements
    this.domElements = {};

    this.init();
  }

  // Utility function to add delays between API calls
  delay(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  // CDN Fallback Management with retry mechanism
  async checkCDNWithRetry(retries = 3) {
    for (let i = 0; i < retries; i++) {
      if (await this.checkCDNAvailability()) {
        return true;
      }
      await this.delay(this.CONSTANTS.CDN_RETRY_BASE_DELAY * Math.pow(2, i)); // Exponential backoff: 1s, 2s, 4s
    }
    return false;
  }

  checkCDNAvailability() {
    console.log("🔍 Checking CDN availability...");

    // Check Chart.js availability
    if (typeof Chart === "undefined") {
      this.cdnFallbacks.chartjs = true;
      console.warn("⚠️ Chart.js CDN failed - using fallback rendering");
      this.showNotification(
        "Chart.js unavailable - using simplified charts",
        "warning",
      );
    }

    // Check date-fns availability
    if (
      typeof dateFns === "undefined" &&
      typeof window.dateFns === "undefined"
    ) {
      this.cdnFallbacks.dateFns = true;
      console.warn("⚠️ date-fns CDN failed - using native Date functions");
    }

    // Check Font Awesome (by checking if FA icons are loaded)
    const testIcon = document.createElement("i");
    testIcon.className = "fas fa-test";
    testIcon.style.visibility = "hidden";
    testIcon.style.position = "absolute";
    document.body.appendChild(testIcon);

    const computedStyle = window.getComputedStyle(testIcon, ":before");
    if (computedStyle.content === "none" || computedStyle.content === "") {
      this.cdnFallbacks.fontAwesome = true;
      console.warn("⚠️ Font Awesome CDN failed - using fallback icons");
    }
    document.body.removeChild(testIcon);

    // Apply fallback styles if needed
    if (Object.values(this.cdnFallbacks).some((failed) => failed)) {
      this.applyCDNFallbacks();
    }
  }

  applyCDNFallbacks() {
    console.log("🔧 Applying CDN fallbacks...");

    // Font Awesome fallback - replace icons with Unicode symbols
    if (this.cdnFallbacks.fontAwesome) {
      const iconMappings = {
        "fa-github": "⚡",
        "fa-clock": "🕒",
        "fa-chart-line": "📈",
        "fa-server": "🖥️",
        "fa-play": "▶️",
        "fa-refresh": "🔄",
        "fa-cog": "⚙️",
        "fa-info": "ℹ️",
        "fa-warning": "⚠️",
        "fa-check": "✅",
        "fa-times": "❌",
      };

      Object.entries(iconMappings).forEach(([faClass, unicode]) => {
        const icons = document.querySelectorAll(`i.${faClass}`);
        icons.forEach((icon) => {
          icon.textContent = unicode;
          icon.style.fontFamily = "system-ui, sans-serif";
          icon.style.fontStyle = "normal";
        });
      });
    }
  }

  // Fallback chart rendering for when Chart.js is unavailable
  renderFallbackChart(canvasId, data) {
    const canvas = document.getElementById(canvasId);
    if (!canvas) {
      return;
    }

    const ctx = canvas.getContext("2d");
    const width = canvas.width;
    const height = canvas.height;

    // Clear canvas
    ctx.clearRect(0, 0, width, height);

    // Simple fallback visualization
    ctx.fillStyle = "#e3f2fd";
    ctx.fillRect(0, 0, width, height);

    ctx.fillStyle = "#1976d2";
    ctx.font = "14px system-ui, sans-serif";
    ctx.textAlign = "center";
    ctx.fillText("Chart data available", width / 2, height / 2 - 10);
    ctx.fillText("(Chart.js CDN unavailable)", width / 2, height / 2 + 10);

    // Simple bar representation if data is available
    if (data && Array.isArray(data) && data.length > 0) {
      const barWidth = Math.max(2, (width - 40) / data.length);
      const maxValue = Math.max(
        ...data.map((d) => (typeof d === "number" ? d : d.value || 0)),
      );

      data.forEach((item, index) => {
        const value = typeof item === "number" ? item : item.value || 0;
        const barHeight = maxValue > 0 ? (value / maxValue) * (height - 60) : 0;
        const x = 20 + index * barWidth;
        const y = height - 30 - barHeight;

        ctx.fillStyle = "#4caf50";
        ctx.fillRect(x, y, barWidth - 2, barHeight);
      });
    }
  }

  // Safe date formatting without date-fns dependency
  formatDateSafe(date) {
    if (this.cdnFallbacks.dateFns) {
      // Fallback to native Date methods
      return new Date(date).toLocaleString("en-US", {
        year: "numeric",
        month: "short",
        day: "numeric",
        hour: "2-digit",
        minute: "2-digit",
      });
    } else if (typeof dateFns !== "undefined") {
      return dateFns.format(new Date(date), "MMM dd, yyyy HH:mm");
    } else if (typeof window.dateFns !== "undefined") {
      return window.dateFns.format(new Date(date), "MMM dd, yyyy HH:mm");
    } else {
      return new Date(date).toLocaleString();
    }
  }

  async init() {
    console.log("🚀 Initializing OCI Orchestrator Dashboard...");

    // Check CDN availability and apply fallbacks if needed
    this.checkCDNAvailability();

    // Setup offline mode detection
    this.setupOfflineHandlers();
    this.checkOfflineStatus();

    // Load saved config
    this.loadConfig();

    // Check if this is first-time setup
    const isFirstTime = !this.config.owner || !this.config.repo;

    // Initialize UI
    this.initializeUI();

    // Setup event listeners
    this.setupEventListeners();

    // Show first-time setup if needed
    if (isFirstTime) {
      console.log("👋 First-time setup detected");
      setTimeout(
        () => this.showFirstTimeSetup(),
        this.CONSTANTS.FIRST_TIME_SETUP_DELAY,
      );
    }

    // Load initial data
    await this.refreshData();

    // Start auto-refresh if enabled
    if (this.config.autoRefresh) {
      this.startAutoRefresh();
    }

    console.log("✅ Dashboard initialized successfully");
  }

  /**
   * Helper methods for safe DOM manipulation
   * Updates the last update display with safe DOM operations
   * @param {Date} date - The date to display
   */
  updateLastUpdateDisplay(date) {
    const element = document.getElementById("last-update");
    if (!element) {
      return;
    }

    // Clear existing content
    element.textContent = "";

    // Create icon
    const icon = document.createElement("i");
    icon.className = "far fa-clock";
    element.appendChild(icon);

    // Create time span
    const timeSpan = document.createElement("span");
    timeSpan.textContent = this.formatTime(date);
    element.appendChild(timeSpan);
  }

  /**
   * Create safe HTML element for workflow run display
   * @param {Object} run - Workflow run data from GitHub API
   * @returns {HTMLElement} Fully constructed workflow run element
   */
  createWorkflowRunHTML(run) {
    const div = document.createElement("div");
    div.className = `workflow-item ${run.conclusion || "running"}`;

    // Status icon
    const statusIcon = document.createElement("div");
    statusIcon.className = "workflow-status";
    const icon = document.createElement("i");

    if (run.status === "in_progress") {
      icon.className = "fas fa-circle-notch fa-spin";
    } else {
      switch (run.conclusion) {
        case "success":
          icon.className = "fas fa-check-circle";
          break;
        case "failure":
          icon.className = "fas fa-times-circle";
          break;
        case "cancelled":
          icon.className = "fas fa-ban";
          break;
        default:
          icon.className = "fas fa-clock";
      }
    }
    statusIcon.appendChild(icon);
    div.appendChild(statusIcon);

    // Content
    const content = document.createElement("div");
    content.className = "workflow-content";

    const title = document.createElement("div");
    title.className = "workflow-title";
    title.textContent = run.display_title || run.name || "Workflow Run";

    const meta = document.createElement("div");
    meta.className = "workflow-meta";
    meta.textContent = `${run.event} • ${this.formatTimeAgo(run.created_at)}`;

    content.appendChild(title);
    content.appendChild(meta);
    div.appendChild(content);

    // Duration
    const duration = document.createElement("div");
    duration.className = "workflow-duration";
    if (run.updated_at && run.created_at) {
      const durationMs = new Date(run.updated_at) - new Date(run.created_at);
      duration.textContent = this.formatDuration(durationMs);
    } else {
      duration.textContent = "--";
    }
    div.appendChild(duration);

    return div;
  }

  createLoadingDiv(message) {
    const div = document.createElement("div");
    div.className = "loading";

    if (message.includes("fa-")) {
      // Message contains Font Awesome icon
      const iconMatch = message.match(/<i class="([^"]+)"><\/i>/);
      if (iconMatch) {
        const icon = document.createElement("i");
        icon.className = iconMatch[1];
        div.appendChild(icon);
        div.appendChild(
          document.createTextNode(message.replace(/<i[^>]*><\/i>\s*/, "")),
        );
      } else {
        div.textContent = message;
      }
    } else {
      div.textContent = message;
    }

    return div;
  }

  createADItemDiv(ad, stats) {
    const div = document.createElement("div");
    div.className = "ad-item";

    // AD name
    const nameDiv = document.createElement("div");
    nameDiv.className = "ad-name";
    nameDiv.textContent = ad.split(":")[1] || ad;
    div.appendChild(nameDiv);

    // Stats container
    const statsDiv = document.createElement("div");
    statsDiv.className = "ad-stats";

    // Success rate
    const successRate =
      stats.total > 0
        ? Math.round(
            (stats.success / stats.total) *
              this.CONSTANTS.PERCENTAGE_MULTIPLIER,
          )
        : 0;
    const successDiv = document.createElement("div");
    successDiv.className = "ad-stat";
    successDiv.textContent = `${successRate}% success`;
    statsDiv.appendChild(successDiv);

    // Attempts
    const attemptsDiv = document.createElement("div");
    attemptsDiv.className = "ad-stat";
    attemptsDiv.textContent = `${stats.total} attempts`;
    statsDiv.appendChild(attemptsDiv);

    div.appendChild(statsDiv);
    return div;
  }

  createScheduleCard(rec) {
    const div = document.createElement("div");
    div.className = "schedule-card";

    // Title
    const title = document.createElement("div");
    title.className = "schedule-title";
    title.textContent = rec.title;
    div.appendChild(title);

    // Description
    const description = document.createElement("div");
    description.className = "schedule-details";
    description.textContent = rec.description;
    div.appendChild(description);

    // Metrics container
    const metrics = document.createElement("div");
    metrics.className = "schedule-metrics";

    // Cron metric
    const cronMetric = document.createElement("div");
    cronMetric.className = "metric";
    cronMetric.textContent = `Cron: ${rec.cron}`;
    metrics.appendChild(cronMetric);

    // Frequency metric
    const freqMetric = document.createElement("div");
    freqMetric.className = "metric";
    freqMetric.textContent = rec.frequency;
    metrics.appendChild(freqMetric);

    // Usage metric
    const usageMetric = document.createElement("div");
    usageMetric.className = "metric";
    usageMetric.textContent = rec.usage;
    metrics.appendChild(usageMetric);

    div.appendChild(metrics);
    return div;
  }

  showFirstTimeSetup() {
    // Show welcome message and settings modal
    this.showNotification(
      "Welcome! Please configure your repository settings to get started.",
      "info",
    );

    // Pre-fill detected values
    if (this.config.owner) {
      document.getElementById("repo-owner").value = this.config.owner;
    }
    if (this.config.repo) {
      document.getElementById("repo-name").value = this.config.repo;
    }

    // Open settings modal automatically
    this.openModal("settings-modal");
  }

  loadConfig() {
    const saved = localStorage.getItem("oic-dashboard-config");
    if (saved) {
      this.config = { ...this.config, ...JSON.parse(saved) };
    }

    // Auto-detect from URL if possible
    if (!this.config.owner || !this.config.repo) {
      this.autoDetectRepo();
    }
  }

  saveConfig() {
    localStorage.setItem("oic-dashboard-config", JSON.stringify(this.config));
  }

  autoDetectRepo() {
    // Try to detect from GitHub Pages URL
    const hostname = window.location.hostname;
    if (hostname.includes("github.io")) {
      const parts = hostname.split(".");
      if (parts.length >= 2) {
        this.config.owner = parts[0];
        // Try to detect repo from pathname
        const path = window.location.pathname;
        const pathParts = path.split("/").filter((p) => p);

        // Handle GitHub Pages URL structure: username.github.io/repo-name/path
        // For https://senomorf.github.io/OracleInstanceCreator/dashboard/
        // pathParts = ['OracleInstanceCreator', 'dashboard']
        if (pathParts.length > 0) {
          // First path segment is the repository name
          this.config.repo = pathParts[0];
          console.log(
            `🔍 Auto-detected repository: ${this.config.owner}/${this.config.repo}`,
          );
        }
      }
    }

    // If not GitHub Pages, try to detect from other hosting patterns
    if (!this.config.owner || !this.config.repo) {
      console.warn(
        "⚠️ Could not auto-detect repository from URL. Please configure manually.",
      );
    }
  }

  initializeUI() {
    // Cache frequently accessed DOM elements
    this.cacheDOMElements();

    // Initialize charts
    this.initCharts();

    // Update connection status
    this.updateConnectionStatus();

    // Show current config in UI
    this.updateConfigUI();
  }

  cacheDOMElements() {
    // Cache frequently used DOM elements to improve performance
    const elementIds = [
      "instance-status",
      "instance-trend",
      "success-rate",
      "success-trend",
      "workflow-runs",
      "cost-estimation",
      "workflow-count",
      "success-count",
      "failure-count",
      "last-update",
      "connection-status",
      "config-status",
      "token-status",
      "repo-info",
      "settings-btn",
    ];

    elementIds.forEach((id) => {
      const element = document.getElementById(id);
      if (element) {
        this.domElements[id] = element;
      } else {
        console.warn(`DOM element with id '${id}' not found`);
      }
    });
  }

  // Helper method to get cached DOM elements (fallback to getElementById)
  getElement(id) {
    return this.domElements[id] || document.getElementById(id);
  }

  /**
   * Calculate exponential backoff delay with jitter
   * @param {number} retryCount - Current retry attempt (0-based)
   * @param {number} [baseDelay=1000] - Base delay in milliseconds
   * @param {number} [maxDelay=30000] - Maximum delay cap in milliseconds
   * @returns {number} Calculated delay in milliseconds with jitter applied
   */
  calculateExponentialBackoff(
    retryCount,
    baseDelay = this.CONSTANTS.EXPONENTIAL_BASE_DELAY,
    maxDelay = this.CONSTANTS.EXPONENTIAL_MAX_DELAY,
  ) {
    const delay = Math.min(baseDelay * Math.pow(2, retryCount), maxDelay);
    // Add jitter to prevent thundering herd
    const jitter = Math.random() * this.CONSTANTS.JITTER_FACTOR * delay;
    return Math.floor(delay + jitter);
  }

  /**
   * Calculate dynamic backoff based on current rate limit state and retry count
   * Uses sophisticated logic considering remaining quota, reset time, and exponential backoff
   * @param {number} [baseDelay=800] - Base delay in milliseconds
   * @param {number} [retryCount=0] - Number of retry attempts for exponential backoff
   * @returns {number} Calculated delay in milliseconds with adaptive multiplier and jitter
   */
  calculateDynamicBackoff(
    baseDelay = this.CONSTANTS.DEFAULT_BASE_DELAY,
    retryCount = 0,
  ) {
    const remaining =
      this.rateLimitState.remaining ||
      this.CONSTANTS.RATE_LIMIT_DEFAULT_REMAINING;

    // Exponential backoff based on retry count
    const exponentialMultiplier = retryCount > 0 ? Math.pow(2, retryCount) : 1;

    // Rate limit based backoff based on remaining quota
    let rateLimitMultiplier = 1;
    if (remaining < this.CONSTANTS.RATE_LIMIT_CRITICAL_THRESHOLD) {
      rateLimitMultiplier = 8; // Very aggressive backoff when critically low
    } else if (remaining < this.CONSTANTS.RATE_LIMIT_LOW_THRESHOLD) {
      rateLimitMultiplier = 4; // Strong backoff when low
    } else if (remaining < this.CONSTANTS.RATE_LIMIT_WARNING_THRESHOLD) {
      rateLimitMultiplier = 2.5; // Moderate backoff when getting low
    }

    // Add additional check for approaching threshold
    if (
      remaining < this.CONSTANTS.RATE_LIMIT_APPROACHING_THRESHOLD &&
      rateLimitMultiplier === 1
    ) {
      rateLimitMultiplier = 1.5; // Light backoff when approaching limits
    }

    // Combine both multipliers for comprehensive backoff
    let multiplier = exponentialMultiplier * rateLimitMultiplier;

    // Add time-based component if reset time is known
    if (this.rateLimitState.resetTime) {
      const now = new Date();
      const timeUntilReset = this.rateLimitState.resetTime - now;
      const minutesUntilReset = Math.max(
        0,
        Math.floor(timeUntilReset / this.CONSTANTS.MS_PER_MINUTE),
      );

      // If reset is soon but we're low on requests, be more conservative
      if (
        minutesUntilReset < this.CONSTANTS.RATE_LIMIT_WARNING_RESET_MINUTES &&
        remaining < this.CONSTANTS.RATE_LIMIT_WARNING_RESET_REMAINING
      ) {
        multiplier = multiplier * 2;
      }
    }

    const delay = baseDelay * multiplier;

    // Add jitter to prevent thundering herd effect
    const jitter = Math.random() * this.CONSTANTS.JITTER_FACTOR * delay;
    const finalDelay = Math.floor(delay + jitter);

    // Log for debugging when using aggressive backoff
    if (multiplier > 2) {
      console.log(
        `🐌 Dynamic backoff: ${finalDelay}ms (${remaining} requests remaining, multiplier: ${multiplier.toFixed(1)})`,
      );
    }

    return finalDelay;
  }

  /**
   * API call wrapper with exponential backoff for rate limits
   * Automatically retries rate limit errors with increasing delays
   * @param {Function} apiFunction - The API function to call with backoff
   * @param {...any} args - Arguments to pass to the API function
   * @returns {Promise<any>} Result from the API function
   * @throws {Error} Throws last error if all retries exhausted
   */
  async apiCallWithBackoff(apiFunction, ...args) {
    let lastError;

    for (
      let attempt = 0;
      attempt <= this.rateLimitState.maxRetries;
      attempt++
    ) {
      try {
        const result = await apiFunction.apply(this, args);
        // Reset retry count on successful call
        this.rateLimitState.retryCount = 0;
        return result;
      } catch (error) {
        lastError = error;

        // Only retry on rate limit errors
        if (
          error.message.includes("Rate limit exceeded") &&
          attempt < this.rateLimitState.maxRetries
        ) {
          const delay = this.calculateDynamicBackoff(
            this.rateLimitState.baseDelay,
            attempt,
          );
          console.warn(
            `Rate limit retry ${attempt + 1}/${this.rateLimitState.maxRetries}, waiting ${delay}ms`,
          );
          await this.delay(delay);
          continue;
        }

        // Don't retry other types of errors or if max retries exceeded
        throw error;
      }
    }

    throw lastError;
  }

  // Safe calculation of minutes remaining with bounds checking
  calculateMinutesRemaining(resetTime) {
    if (
      !resetTime ||
      !(resetTime instanceof Date) ||
      isNaN(resetTime.getTime())
    ) {
      console.warn("Invalid reset time provided for rate limit calculation");
      return 60; // Default to 1 hour if invalid
    }

    const now = new Date();
    const msRemaining = resetTime.getTime() - now.getTime();

    // Ensure positive value and reasonable bounds (max 60 minutes)
    const minutesRemaining = Math.max(
      0,
      Math.ceil(msRemaining / this.CONSTANTS.MS_PER_MINUTE),
    );
    return Math.min(minutesRemaining, 60);
  }

  // Safe parsing of reset time with validation
  parseResetTime(resetTimeHeader) {
    if (!resetTimeHeader) {
      return null;
    }

    const resetTimestamp = parseInt(resetTimeHeader);
    if (isNaN(resetTimestamp) || resetTimestamp <= 0) {
      console.warn("Invalid reset time header:", resetTimeHeader);
      return null;
    }

    // Ensure timestamp is reasonable (not too far in the future or past)
    const resetTime = new Date(resetTimestamp * 1000);
    const now = new Date();
    const hourFromNow = new Date(now.getTime() + this.CONSTANTS.MS_PER_HOUR);
    const hourAgo = new Date(now.getTime() - this.CONSTANTS.MS_PER_HOUR);

    if (resetTime < hourAgo || resetTime > hourFromNow) {
      console.warn("Reset time is outside reasonable bounds:", resetTime);
      return new Date(now.getTime() + this.CONSTANTS.MS_PER_HOUR); // Default to 1 hour from now
    }

    return resetTime;
  }

  initCharts() {
    // Check if Chart.js is available
    if (typeof Chart === "undefined" || this.cdnFallbacks.chartjs) {
      console.warn("⚠️ Chart.js not available - using fallback visualization");
      this.initFallbackCharts();
      return;
    }

    try {
      // Success Pattern Chart
      const successCtx = document.getElementById("success-pattern-chart");
      if (successCtx) {
        this.charts.successPattern = new Chart(successCtx, {
          type: "line",
          data: {
            labels: [],
            datasets: [
              {
                label: "Success Rate %",
                data: [],
                borderColor: "#10b981",
                backgroundColor: "rgba(16, 185, 129, 0.1)",
                borderWidth: 2,
                fill: true,
                tension: 0.4,
              },
            ],
          },
          options: {
            responsive: true,
            maintainAspectRatio: false,
            scales: {
              y: {
                beginAtZero: true,
                max: 100,
                ticks: {
                  callback: function (value) {
                    return value + "%";
                  },
                },
              },
            },
            plugins: {
              legend: {
                display: false,
              },
            },
          },
        });
      }

      // Usage Chart
      const usageCtx = document.getElementById("usage-chart");
      if (usageCtx) {
        this.charts.usage = new Chart(usageCtx, {
          type: "doughnut",
          data: {
            labels: ["Used", "Remaining"],
            datasets: [
              {
                data: [0, 2000],
                backgroundColor: ["#f59e0b", "#e5e7eb"],
                borderWidth: 0,
              },
            ],
          },
          options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
              legend: {
                position: "bottom",
              },
            },
          },
        });
      }

      console.log("✅ Charts initialized successfully");
    } catch (error) {
      console.error("❌ Error initializing charts:", error);
      this.cdnFallbacks.chartjs = true;
      this.initFallbackCharts();
    }
  }

  initFallbackCharts() {
    // Initialize fallback visualization when Chart.js is not available
    const successCanvas = document.getElementById("success-pattern-chart");
    const usageCanvas = document.getElementById("usage-chart");

    if (successCanvas) {
      this.renderFallbackChart("success-pattern-chart", [], "line");
    }

    if (usageCanvas) {
      this.renderFallbackChart("usage-chart", [0, 2000], "doughnut");
    }

    console.log("📊 Fallback charts initialized");
  }

  setupEventListeners() {
    // Settings button
    document.getElementById("settings-btn").addEventListener("click", () => {
      this.openModal("settings-modal");
    });

    // Close modal
    document.querySelector(".close").addEventListener("click", () => {
      this.closeModal();
    });

    // Save settings
    document.getElementById("save-settings").addEventListener("click", () => {
      this.saveSettings();
    });

    // Control buttons
    document
      .getElementById("trigger-workflow")
      .addEventListener("click", () => {
        this.triggerWorkflow();
      });

    document.getElementById("reset-success").addEventListener("click", () => {
      this.resetSuccessState();
    });

    document.getElementById("export-data").addEventListener("click", () => {
      this.exportData();
    });

    document.getElementById("view-logs").addEventListener("click", () => {
      this.viewLogs();
    });

    // Refresh button
    document.getElementById("refresh-runs").addEventListener("click", () => {
      this.refreshData();
    });

    // Chart controls
    document
      .getElementById("pattern-timeframe")
      .addEventListener("change", (e) => {
        this.updateSuccessPatternChart(parseInt(e.target.value));
      });

    document.getElementById("usage-view").addEventListener("change", (e) => {
      this.updateUsageChart(e.target.value);
    });

    // Region selector
    document
      .getElementById("region-selector")
      .addEventListener("change", (e) => {
        this.updateRegionalAnalysis(e.target.value);
      });

    // Modal close on outside click
    window.addEventListener("click", (e) => {
      if (e.target.classList.contains("modal")) {
        this.closeModal();
      }
    });

    // Cleanup on page unload to prevent memory leaks
    window.addEventListener("beforeunload", () => {
      this.cleanup();
    });
  }

  /**
   * Main data refresh method with rate limiting and error handling
   * Orchestrates loading of all dashboard data with proper delays
   * @returns {Promise<void>}
   */
  async refreshData() {
    console.log("🔄 Refreshing dashboard data...");

    // Prevent overlapping refresh operations
    if (this.refreshInProgress) {
      console.log("⏭️ Refresh already in progress, skipping...");
      return;
    }

    this.refreshInProgress = true;

    try {
      // Check if basic configuration is available
      if (!this.config.owner || !this.config.repo) {
        console.warn("⚠️ Repository not configured. Showing setup prompt.");
        this.showConfigurationPrompt();
        this.refreshInProgress = false;
        return;
      }

      // If offline, use cached data instead of making API calls
      if (this.offlineMode.enabled) {
        console.log("📵 Offline mode - using cached data");
        this.loadCachedData();
        this.refreshInProgress = false;
        return;
      }

      // Update last update time
      this.lastUpdate = new Date();
      this.updateLastUpdateDisplay(this.lastUpdate);

      // Load public data with staggered requests to avoid rate limiting
      console.log("📊 Loading public data...");
      await this.updateWorkflowRuns();
      // Dynamic exponential backoff based on rate limit state
      const backoff = this.calculateDynamicBackoff();
      await this.delay(backoff);

      await this.updateUsageMetrics();
      // Dynamic exponential backoff based on rate limit state
      const backoff2 = this.calculateDynamicBackoff();
      await this.delay(backoff2);

      await this.updateScheduleInfo();

      // Only load authenticated data if token is available
      if (this.config.token) {
        console.log("🔐 Loading authenticated data...");
        await this.delay(this.CONSTANTS.AUTH_CALLS_INITIAL_DELAY); // Longer delay before authenticated calls

        await this.updateInstanceStatus();
        // Dynamic exponential backoff based on rate limit state
        const backoff3 = this.calculateDynamicBackoff();
        await this.delay(backoff3);

        await this.updateSuccessMetrics();
        // Dynamic exponential backoff based on rate limit state
        const backoff4 = this.calculateDynamicBackoff();
        await this.delay(backoff4);

        await this.updateADPerformance();
      } else {
        // Show limited data message for authenticated features
        this.showAuthenticationPrompt();
      }

      // Cache the successful data fetch for offline mode
      this.cacheCurrentData();
    } catch (error) {
      console.error("Error refreshing data:", error);
      this.handleDataLoadError(error);
    } finally {
      // Always reset the refresh flag
      this.refreshInProgress = false;
    }
  }

  showConfigurationPrompt() {
    // Show message for missing repository configuration
    this.getElement("instance-status").textContent = "Not Configured";

    const trendElement = this.getElement("instance-trend");
    trendElement.textContent = "⚙️ ";
    const configLink = document.createElement("a");
    configLink.href = "#";
    configLink.id = "config-link";
    configLink.textContent = "Configure repository settings";
    trendElement.appendChild(configLink);
    configLink.addEventListener("click", (e) => {
      e.preventDefault();
      this.getElement("settings-btn").click();
    });

    const workflowContainer = document.getElementById("workflow-runs");
    if (workflowContainer) {
      workflowContainer.textContent = "";
      const loadingDiv = document.createElement("div");
      loadingDiv.className = "loading";

      const icon = document.createElement("i");
      icon.className = "fas fa-cog";
      loadingDiv.appendChild(icon);
      loadingDiv.appendChild(
        document.createTextNode(
          "Repository not configured. Click settings to get started.",
        ),
      );

      workflowContainer.appendChild(loadingDiv);
    }
  }

  showAuthenticationPrompt() {
    // Show limited access message for features requiring authentication
    this.getElement("instance-status").textContent = "Limited Access";

    const trendElement = this.getElement("instance-trend");
    trendElement.textContent = "🔒 ";
    const tokenLink = document.createElement("a");
    tokenLink.href = "#";
    tokenLink.id = "token-link";
    tokenLink.textContent = "Add GitHub token for full access";
    trendElement.appendChild(tokenLink);
    tokenLink.addEventListener("click", (e) => {
      e.preventDefault();
      this.getElement("settings-btn").click();
    });

    document.getElementById("success-rate").textContent = "---%";
    document.getElementById("success-trend").textContent = "Token required";
  }

  handleDataLoadError(error) {
    if (error.message.includes("GitHub token not configured")) {
      this.showAuthenticationPrompt();
    } else if (error.message.includes("Not Found")) {
      this.showError("Repository not found. Please check your configuration.");
    } else {
      this.showError("Failed to refresh data: " + error.message);
    }
  }

  async updateInstanceStatus() {
    try {
      // Get repository variables to check instance status
      const variables = await this.githubAPI(
        "/repos/" +
          this.config.owner +
          "/" +
          this.config.repo +
          "/actions/variables",
      );

      const instanceCreated = variables.variables?.find(
        (v) => v.name === "INSTANCE_CREATED",
      );
      const instanceInfo = variables.variables?.find(
        (v) => v.name === "INSTANCE_CREATED_INFO",
      );

      let status = "No Instance";
      let trend = "Checking availability...";

      if (instanceCreated && instanceCreated.value === "true") {
        status = "Instance Active";
        trend = "✅ Instance successfully created";

        if (instanceInfo) {
          try {
            const info = JSON.parse(instanceInfo.value);
            trend = `✅ Created in ${info.ad} at ${this.formatTime(new Date(info.timestamp))}`;
          } catch (e) {
            console.warn("Failed to parse instance info:", e);
            // Use default trend
          }
        }
      } else {
        trend = "🔍 Actively searching for capacity...";
      }

      document.getElementById("instance-status").textContent = status;
      document.getElementById("instance-trend").textContent = trend;
    } catch (error) {
      console.error("Error updating instance status:", error);
      document.getElementById("instance-status").textContent = "Unknown";
      document.getElementById("instance-trend").textContent =
        "Error fetching status";
    }
  }

  async updateWorkflowRuns() {
    try {
      // Use public API for workflow runs - no authentication required
      const runs = await this.githubPublicAPI(
        `/repos/${this.config.owner}/${this.config.repo}/actions/runs?per_page=10`,
      );

      const container = document.getElementById("workflow-runs");

      if (!runs.workflow_runs || runs.workflow_runs.length === 0) {
        container.textContent = "";
        container.appendChild(this.createLoadingDiv("No workflow runs found"));
        return;
      }

      // Clear container and add workflow runs safely
      container.textContent = "";
      runs.workflow_runs.forEach((run) => {
        container.appendChild(this.createWorkflowRunHTML(run));
      });
    } catch (error) {
      const container = document.getElementById("workflow-runs");
      container.textContent = "";

      let message;
      if (error.message.includes("rate limit")) {
        message = "⏳ Rate limited - please wait and refresh";
      } else if (error.message.includes("not found")) {
        message = "❌ Repository not found or not public";
      } else {
        message = "❌ Error loading workflow runs";
      }

      container.appendChild(this.createLoadingDiv(message));
      console.error("Error loading workflow runs:", error);
    }
  }

  async updateSuccessMetrics() {
    try {
      // Get pattern data from repository variables
      const variables = await this.githubAPI(
        `/repos/${this.config.owner}/${this.config.repo}/actions/variables`,
      );
      const patternData = variables.variables?.find(
        (v) => v.name === "SUCCESS_PATTERN_DATA",
      );

      let successRate = 0;
      let trend = "No data available";

      if (patternData) {
        try {
          const patterns = JSON.parse(patternData.value);
          const totalAttempts = patterns.length;
          const successes = patterns.filter((p) => p.type === "success").length;

          if (totalAttempts > 0) {
            successRate = Math.round((successes / totalAttempts) * 100);
            trend = `${successes}/${totalAttempts} attempts successful`;
          }
        } catch (e) {
          console.error("Error parsing pattern data:", e);
        }
      }

      document.getElementById("success-rate").textContent = `${successRate}%`;
      document.getElementById("success-trend").textContent = trend;

      // Update success pattern chart
      let chartData = [];
      if (patternData) {
        try {
          chartData = JSON.parse(patternData.value);
        } catch (e) {
          console.error("Error parsing pattern data for chart:", e);
        }
      }
      this.updateSuccessPatternChart(30, chartData);
    } catch (error) {
      console.error("Error updating success metrics:", error);
      document.getElementById("success-rate").textContent = "---%";
      document.getElementById("success-trend").textContent =
        "Error loading metrics";
    }
  }

  updateUsageMetrics() {
    try {
      // Calculate estimated usage based on current schedule
      const now = new Date();
      const daysInMonth = new Date(
        now.getFullYear(),
        now.getMonth() + 1,
        0,
      ).getDate();
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

      document.getElementById("usage-percentage").textContent =
        `${usagePercentage}%`;
      document.getElementById("usage-trend").textContent =
        `${currentMonthMinutes}/${estimatedMonthlyMinutes} min projected`;

      // Update usage chart if available
      if (this.charts?.usage && !this.cdnFallbacks.chartjs) {
        this.charts.usage.data.datasets[0].data = [
          currentMonthMinutes,
          Math.max(0, remainingMinutes),
        ];
        this.charts.usage.data.datasets[0].backgroundColor = [
          usagePercentage > 80
            ? "#ef4444"
            : usagePercentage > 60
              ? "#f59e0b"
              : "#10b981",
          "#e5e7eb",
        ];
        this.charts.usage.update();
      } else {
        // Use fallback chart rendering
        this.renderFallbackChart(
          "usage-chart",
          [currentMonthMinutes, Math.max(0, remainingMinutes)],
          "doughnut",
        );
      }
    } catch (error) {
      console.error("Error updating usage metrics:", error);
      document.getElementById("usage-percentage").textContent = "---%";
      document.getElementById("usage-trend").textContent =
        "Error calculating usage";
    }
  }

  async updateADPerformance() {
    try {
      const variables = await this.githubAPI(
        `/repos/${this.config.owner}/${this.config.repo}/actions/variables`,
      );
      const patternData = variables.variables?.find(
        (v) => v.name === "SUCCESS_PATTERN_DATA",
      );

      const container = document.getElementById("ad-stats");

      if (!patternData) {
        container.textContent = "";
        container.appendChild(
          this.createLoadingDiv("No AD performance data available"),
        );
        return;
      }

      let patterns = [];
      try {
        patterns = JSON.parse(patternData.value);
      } catch (e) {
        console.error("Error parsing AD performance data:", e);
        container.textContent = "";
        container.appendChild(
          this.createLoadingDiv("Invalid AD performance data"),
        );
        return;
      }

      const adStats = {};

      patterns.forEach((pattern) => {
        if (pattern.ad && pattern.ad !== "VERIFIED") {
          if (!adStats[pattern.ad]) {
            adStats[pattern.ad] = { total: 0, success: 0 };
          }
          adStats[pattern.ad].total++;
          if (pattern.type === "success") {
            adStats[pattern.ad].success++;
          }
        }
      });

      container.textContent = "";

      if (Object.keys(adStats).length === 0) {
        container.appendChild(this.createLoadingDiv("No AD data available"));
      } else {
        Object.entries(adStats).forEach(([ad, stats]) => {
          container.appendChild(this.createADItemDiv(ad, stats));
        });
      }
      document.getElementById("ad-update-time").textContent =
        `Updated: ${this.formatTime(new Date())}`;
    } catch (error) {
      console.error("Error updating AD performance:", error);
      const container = document.getElementById("ad-stats");
      container.textContent = "";
      container.appendChild(this.createLoadingDiv("Error loading AD stats"));
    }
  }

  updateScheduleInfo() {
    try {
      // Calculate next run time based on cron schedules
      const nextRun = this.calculateNextRun();
      document.getElementById("next-run").textContent =
        this.formatTime(nextRun);

      // Determine current schedule context
      const context = this.getCurrentScheduleContext();
      document.getElementById("schedule-context").textContent = context;
    } catch (error) {
      console.error("Error updating schedule info:", error);
      document.getElementById("next-run").textContent = "--:--";
      document.getElementById("schedule-context").textContent =
        "Error calculating schedule";
    }
  }

  updateSuccessPatternChart(days, data = null) {
    // Use fallback rendering if Chart.js is unavailable or charts not initialized
    if (this.cdnFallbacks.chartjs || !this.charts?.successPattern) {
      const chartData = data
        ? this.processChartData(data, days)
        : this.generateMockChartData(days);
      this.renderFallbackChart("success-pattern-chart", chartData, "line");
      return;
    }

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

      data.forEach((pattern) => {
        const date = new Date(pattern.timestamp).toDateString();
        if (new Date(pattern.timestamp) >= cutoffDate) {
          if (!dailyStats[date]) {
            dailyStats[date] = { total: 0, success: 0 };
          }
          dailyStats[date].total++;
          if (pattern.type === "success") {
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

  // Helper methods for CDN fallback chart data processing
  processChartData(data, days) {
    const dailyStats = {};
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - days);

    data.forEach((pattern) => {
      const date = new Date(pattern.timestamp).toDateString();
      if (new Date(pattern.timestamp) >= cutoffDate) {
        if (!dailyStats[date]) {
          dailyStats[date] = { total: 0, success: 0 };
        }
        dailyStats[date].total++;
        if (pattern.type === "success") {
          dailyStats[date].success++;
        }
      }
    });

    const chartData = [];
    for (let i = days - 1; i >= 0; i--) {
      const date = new Date();
      date.setDate(date.getDate() - i);
      const dateStr = date.toDateString();

      const stats = dailyStats[dateStr];
      if (stats && stats.total > 0) {
        chartData.push(Math.round((stats.success / stats.total) * 100));
      } else {
        chartData.push(0);
      }
    }

    return chartData;
  }

  generateMockChartData(days) {
    const mockData = [];
    for (let i = 0; i < days; i++) {
      mockData.push(Math.floor(Math.random() * 100));
    }
    return mockData;
  }

  // Setup offline event handlers
  setupOfflineHandlers() {
    window.addEventListener("online", () => {
      console.log("🌐 Connection restored");
      this.checkOfflineStatus();
    });

    window.addEventListener("offline", () => {
      console.log("📵 Connection lost");
      this.checkOfflineStatus();
    });

    // Check periodically as well (navigator.onLine can be unreliable)
    this.offlineTimer = setInterval(() => {
      this.checkOfflineStatus();
    }, 30000); // Check every 30 seconds
  }

  // Offline Mode Management
  checkOfflineStatus() {
    const isOnline = navigator.onLine;
    const wasOffline = this.offlineMode.enabled;

    this.offlineMode.enabled = !isOnline;

    // Show/hide offline indicator
    const offlineIndicator = document.getElementById("offline-indicator");
    if (!offlineIndicator) {
      this.createOfflineIndicator();
    }

    if (!isOnline && !wasOffline) {
      console.warn("🔌 Dashboard is now offline - using cached data");
      this.showOfflineMode();
    } else if (isOnline && wasOffline) {
      console.log("🌐 Connection restored - refreshing data");
      this.hideOfflineMode();
      this.refreshData();
    }
  }

  createOfflineIndicator() {
    const indicator = document.createElement("div");
    indicator.id = "offline-indicator";
    const banner = document.createElement("div");
    banner.className = "offline-banner";

    const mainText = document.createElement("span");
    mainText.textContent = "📵 Offline Mode";
    banner.appendChild(mainText);

    const subText = document.createElement("small");
    subText.textContent = "Using cached data";
    banner.appendChild(subText);

    indicator.appendChild(banner);
    indicator.style.cssText = `
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            z-index: 1000;
            display: none;
            background: linear-gradient(45deg, #ff9800, #f57c00);
            color: white;
            text-align: center;
            padding: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.2);
        `;
    document.body.appendChild(indicator);
  }

  showOfflineMode() {
    const indicator = document.getElementById("offline-indicator");
    if (indicator) {
      indicator.style.display = "block";
    }

    // Load cached data if available
    this.loadCachedData();

    // Disable refresh functionality
    const refreshBtn = document.getElementById("refresh-data");
    if (refreshBtn) {
      refreshBtn.disabled = true;
      refreshBtn.title = "Cannot refresh in offline mode";
    }

    this.showNotification("Offline mode: Using cached data", "info");
  }

  hideOfflineMode() {
    const indicator = document.getElementById("offline-indicator");
    if (indicator) {
      indicator.style.display = "none";
    }

    // Re-enable refresh functionality
    const refreshBtn = document.getElementById("refresh-data");
    if (refreshBtn) {
      refreshBtn.disabled = false;
      refreshBtn.title = "Refresh dashboard data";
    }

    this.showNotification("Connection restored", "success");
  }

  cacheData(data) {
    try {
      const cacheData = {
        timestamp: new Date().toISOString(),
        data,
      };
      const cacheString = JSON.stringify(cacheData);
      // Check cache size and prune if necessary (50KB limit)
      if (cacheString.length > 50000) {
        console.warn("Cache data exceeding 50KB, pruning old data...");
        this.pruneOldCacheData(cacheData);
        localStorage.setItem("oic-dashboard-cache", JSON.stringify(cacheData));
      } else {
        localStorage.setItem("oic-dashboard-cache", cacheString);
      }
      this.offlineMode.lastDataCache = data;
      this.offlineMode.cacheTimestamp = new Date();
      console.log("💾 Dashboard data cached successfully");
    } catch (error) {
      console.warn("Failed to cache data:", error);
    }
  }

  pruneOldCacheData(cacheData) {
    // Remove oldest entries to reduce cache size
    if (cacheData.data && Array.isArray(cacheData.data.workflowRuns)) {
      // Keep only the last 20 workflow runs instead of all
      cacheData.data.workflowRuns = cacheData.data.workflowRuns.slice(-20);
    }
    if (cacheData.data && Array.isArray(cacheData.data.adPerformance)) {
      // Keep only the last 10 AD performance entries
      cacheData.data.adPerformance = cacheData.data.adPerformance.slice(-10);
    }
    console.log("🗂️ Cache data pruned to reduce size");
  }

  loadCachedData() {
    try {
      const cached = localStorage.getItem("oic-dashboard-cache");
      if (cached) {
        const cacheData = JSON.parse(cached);
        const cacheAge = Date.now() - new Date(cacheData.timestamp).getTime();
        const maxAge = 24 * 60 * 60 * 1000; // 24 hours

        if (cacheAge < maxAge) {
          console.log(
            "📂 Loading cached data (age: " +
              Math.round(cacheAge / 1000 / 60) +
              " minutes)",
          );
          this.displayCachedData(cacheData.data);
          return true;
        } else {
          console.warn("Cached data is too old, clearing cache");
          localStorage.removeItem("oic-dashboard-cache");
        }
      }
    } catch (error) {
      console.error("Failed to load cached data:", error);
    }

    // Show offline message if no cache available
    this.displayOfflineMessage();
    return false;
  }

  displayCachedData(data) {
    // Update UI with cached data
    if (data.instanceStatus) {
      document.getElementById("instance-status").textContent =
        data.instanceStatus;
      document.getElementById("instance-trend").textContent = "Cached data";
    }

    if (data.workflowRuns) {
      const container = document.getElementById("workflow-runs");
      container.textContent = "";

      data.workflowRuns.forEach((run) => {
        const runItem = document.createElement("div");
        const statusClass = this.getRunStatusClass(run.status);
        runItem.className = `run-item ${statusClass.class}`;

        const statusSpan = document.createElement("span");
        statusSpan.className = "run-status";
        statusSpan.textContent = statusClass.text;
        runItem.appendChild(statusSpan);

        const timeSpan = document.createElement("span");
        timeSpan.className = "run-time";
        timeSpan.textContent = `${this.formatDateSafe(run.created_at)} (cached)`;
        runItem.appendChild(timeSpan);

        const durationSpan = document.createElement("span");
        durationSpan.className = "run-duration";
        durationSpan.textContent = `${run.duration || "--"}s`;
        runItem.appendChild(durationSpan);

        container.appendChild(runItem);
      });
    }

    // Update last refresh time
    const lastUpdateEl = document.getElementById("last-update");
    lastUpdateEl.textContent = "";

    const span = document.createElement("span");
    span.textContent = `Last updated (cached): ${this.formatDateSafe(this.offlineMode.cacheTimestamp)}`;
    lastUpdateEl.appendChild(span);
  }

  displayOfflineMessage() {
    // Show offline placeholders
    document.getElementById("instance-status").textContent = "Offline";
    document.getElementById("instance-trend").textContent =
      "No cached data available";

    const workflowContainer = document.getElementById("workflow-runs");
    workflowContainer.textContent = "";

    const loadingDiv = document.createElement("div");
    loadingDiv.className = "loading";

    const icon = document.createElement("i");
    icon.className = "fas fa-wifi";
    icon.style.opacity = "0.5";
    loadingDiv.appendChild(icon);
    loadingDiv.appendChild(
      document.createTextNode("No connection - cached data unavailable"),
    );

    workflowContainer.appendChild(loadingDiv);

    const lastUpdateEl = document.getElementById("last-update");
    lastUpdateEl.textContent = "";

    const span = document.createElement("span");
    span.textContent = "Offline mode - no data available";
    lastUpdateEl.appendChild(span);
  }

  cacheCurrentData() {
    try {
      const currentData = {
        instanceStatus: document.getElementById("instance-status")?.textContent,
        instanceTrend: document.getElementById("instance-trend")?.textContent,
        successRate: document.getElementById("success-rate")?.textContent,
        usagePercentage:
          document.getElementById("usage-percentage")?.textContent,
        workflowRuns: this.getCurrentWorkflowData(),
        lastRefresh: new Date().toISOString(),
      };

      this.cacheData(currentData);
    } catch (error) {
      console.warn("Failed to cache current data:", error);
    }
  }

  getCurrentWorkflowData() {
    const runs = [];
    const runElements = document.querySelectorAll("#workflow-runs .run-item");

    runElements.forEach((element) => {
      const statusElement = element.querySelector(".run-status");
      const timeElement = element.querySelector(".run-time");
      const durationElement = element.querySelector(".run-duration");

      runs.push({
        status: statusElement?.textContent || "Unknown",
        created_at: timeElement?.textContent || new Date().toISOString(),
        duration: durationElement?.textContent?.replace("s", "") || 0,
      });
    });

    return runs;
  }

  updateRegionalAnalysis(region = "auto") {
    const container = document.getElementById("schedule-recommendations");

    // Regional schedule recommendations
    const recommendations = this.getRegionalRecommendations(region);

    container.textContent = "";

    recommendations.forEach((rec) => {
      container.appendChild(this.createScheduleCard(rec));
    });
  }

  getRegionalRecommendations(region) {
    const recommendations = {
      "ap-singapore-1": [
        {
          title: "Off-Peak Aggressive",
          description: "2-7am UTC (10am-3pm SGT) - Lunch/low activity hours",
          cron: "*/15 2-7 * * *",
          frequency: "24 runs/day",
          usage: "720 min/month",
        },
        {
          title: "Peak Conservative",
          description: "8am-1am UTC (4pm-9am SGT) - Avoid business peak",
          cron: "0 8-23,0-1 * * *",
          frequency: "18 runs/day",
          usage: "540 min/month",
        },
        {
          title: "Weekend Boost",
          description:
            "1-6am UTC weekends (9am-2pm SGT) - Lower weekend demand",
          cron: "*/20 1-6 * * 6,0",
          frequency: "18 runs/weekend",
          usage: "144 min/month",
        },
      ],
      "us-east-1": [
        {
          title: "Night Hours Aggressive",
          description: "6-12 UTC (1am-7am EST) - Deep night hours",
          cron: "*/15 6-12 * * *",
          frequency: "24 runs/day",
          usage: "720 min/month",
        },
        {
          title: "Business Hours Conservative",
          description: "13-5 UTC (8am-12am EST) - Avoid business/evening",
          cron: "0 13-23,0-5 * * *",
          frequency: "17 runs/day",
          usage: "510 min/month",
        },
      ],
      "eu-frankfurt-1": [
        {
          title: "Evening Low Activity",
          description: "18-23 UTC (7pm-12am CET) - Evening low usage",
          cron: "*/15 18-23 * * *",
          frequency: "24 runs/day",
          usage: "720 min/month",
        },
        {
          title: "Non-Business Hours",
          description: "0-8,17 UTC (1am-9am,6pm CET) - Outside business",
          cron: "0 0-8,17 * * *",
          frequency: "9 runs/day",
          usage: "270 min/month",
        },
      ],
    };

    return recommendations[region] || recommendations["ap-singapore-1"];
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
      return "Off-peak aggressive (SGT lunch hours)";
    } else if ((day === 0 || day === 6) && hour >= 1 && hour < 6) {
      return "Weekend boost period";
    } else {
      return "Conservative peak hours";
    }
  }

  /**
   * Authenticated GitHub API call with rate limiting
   * @param {string} endpoint - API endpoint path
   * @param {Object} [options={}] - Fetch options
   * @returns {Promise<Object>} Parsed JSON response
   * @throws {Error} API errors or rate limit exceeded
   */
  async githubAPI(endpoint, options = {}) {
    if (!this.config.token) {
      throw new Error("GitHub token not configured");
    }

    const url = `https://api.github.com${endpoint}`;
    const response = await fetch(url, {
      headers: {
        Authorization: `Bearer ${this.config.token}`,
        Accept: "application/vnd.github.v3+json",
        ...options.headers,
      },
      ...options,
    });

    if (!response.ok) {
      throw new Error(
        `GitHub API error: ${response.status} ${response.statusText}`,
      );
    }

    return response.json();
  }

  /**
   * Public GitHub API call (no authentication required)
   * @param {string} endpoint - API endpoint path
   * @param {Object} [options={}] - Fetch options
   * @returns {Promise<Object>} Parsed JSON response
   * @throws {Error} API errors or rate limit exceeded
   */
  async githubPublicAPI(endpoint, options = {}) {
    // Check if we're currently rate limited
    if (this.rateLimitState.exceeded) {
      const now = new Date();
      if (
        this.rateLimitState.resetTime &&
        now < this.rateLimitState.resetTime
      ) {
        const minutesRemaining = this.calculateMinutesRemaining(
          this.rateLimitState.resetTime,
        );
        throw new Error(
          `Rate limit exceeded. Try again in ${minutesRemaining} minute(s).`,
        );
      }
      // Reset state if time has passed
      this.rateLimitState.exceeded = false;
      this.rateLimitState.resetTime = null;
    }

    // Public API calls that don't require authentication
    const url = `https://api.github.com${endpoint}`;
    const response = await fetch(url, {
      headers: {
        Accept: "application/vnd.github.v3+json",
        ...options.headers,
      },
      ...options,
    });

    // Update rate limit information from response headers
    this.updateRateLimitState(response.headers);

    if (!response.ok) {
      if (response.status === 403) {
        // Check if it's rate limiting or forbidden access
        const rateLimitRemaining = response.headers.get(
          "X-RateLimit-Remaining",
        );
        if (rateLimitRemaining === "0") {
          this.rateLimitState.exceeded = true;
          const resetTimeHeader = response.headers.get("X-RateLimit-Reset");
          this.rateLimitState.resetTime = this.parseResetTime(resetTimeHeader);
          const minutesRemaining = this.rateLimitState.resetTime
            ? this.calculateMinutesRemaining(this.rateLimitState.resetTime)
            : 60;
          throw new Error(
            `Rate limit exceeded. Try again in ${minutesRemaining} minute(s).`,
          );
        } else {
          throw new Error(
            "GitHub API access forbidden. Repository may be private.",
          );
        }
      } else if (response.status === 404) {
        throw new Error("Repository not found or not public");
      }
      throw new Error(
        `GitHub API error: ${response.status} ${response.statusText}`,
      );
    }

    return response.json();
  }

  updateRateLimitState(headers) {
    // Update rate limit tracking from response headers
    const remaining = headers.get("X-RateLimit-Remaining");
    const reset = headers.get("X-RateLimit-Reset");

    if (remaining !== null) {
      this.rateLimitState.remaining = parseInt(remaining);
    }
    if (reset !== null) {
      this.rateLimitState.resetTime = new Date(parseInt(reset) * 1000);
    }

    // Log rate limit status for debugging (prevent spam)
    if (
      this.rateLimitState.remaining <
        this.CONSTANTS.RATE_LIMIT_WARNING_THRESHOLD &&
      !this.rateLimitState.warningShown
    ) {
      console.warn(
        `⚠️ GitHub API rate limit low: ${this.rateLimitState.remaining} requests remaining`,
      );
      this.rateLimitState.warningShown = true;
    } else if (
      this.rateLimitState.remaining >=
      this.CONSTANTS.RATE_LIMIT_WARNING_THRESHOLD
    ) {
      // Reset warning flag when rate limit recovers
      this.rateLimitState.warningShown = false;
    }
  }

  getRunStatus(run) {
    switch (run.status) {
      case "completed":
        if (run.conclusion === "success") {
          return { class: "success", text: "Success" };
        } else {
          return { class: "error", text: "Failed" };
        }
      case "in_progress":
        return { class: "running", text: "Running" };
      default:
        return { class: "error", text: run.status };
    }
  }

  calculateDuration(start, end) {
    const startTime = new Date(start);
    const endTime = new Date(end);
    return Math.round((endTime - startTime) / 1000);
  }

  formatTime(date) {
    return date.toLocaleTimeString([], {
      hour: "2-digit",
      minute: "2-digit",
      hour12: false,
    });
  }

  openModal(modalId) {
    document.getElementById(modalId).style.display = "block";
  }

  closeModal() {
    document.querySelectorAll(".modal").forEach((modal) => {
      modal.style.display = "none";
    });
  }

  saveSettings() {
    // Validate input fields
    const owner = document.getElementById("repo-owner").value?.trim();
    const repo = document.getElementById("repo-name").value?.trim();
    const token = document.getElementById("github-token").value?.trim();

    if (!owner || !repo) {
      this.showError("Repository owner and name are required");
      return;
    }

    // Enhanced validation for GitHub username/repo format
    // GitHub usernames: alphanumeric and hyphens, cannot start/end with hyphen, max 39 chars
    // Repo names: alphanumeric, hyphens, underscores, dots, cannot start with dot, max 100 chars
    const validOwner = /^[a-zA-Z0-9]([a-zA-Z0-9-]{0,37}[a-zA-Z0-9])?$/;
    const validRepo = /^[a-zA-Z0-9][a-zA-Z0-9._-]{0,99}$/;

    if (!validOwner.test(owner)) {
      this.showError(
        "Invalid repository owner format (alphanumeric and hyphens only, max 39 chars)",
      );
      return;
    }

    if (!validRepo.test(repo)) {
      this.showError(
        "Invalid repository name format (alphanumeric, dots, hyphens, underscores, max 100 chars)",
      );
      return;
    }

    this.config.token = token;
    this.config.owner = owner;
    this.config.repo = repo;
    this.config.autoRefresh = document.getElementById("auto-refresh").checked;

    this.saveConfig();
    this.updateConnectionStatus();
    this.closeModal();

    // Refresh data with new settings
    this.refreshData();
  }

  updateConnectionStatus() {
    const statusEl = document.getElementById("connection-status");

    statusEl.textContent = "";

    const icon = document.createElement("i");
    icon.className = "fas fa-circle";

    const span = document.createElement("span");

    if (this.config.token && this.config.owner && this.config.repo) {
      icon.style.color = "#10b981";
      span.textContent = "Connected";
    } else {
      icon.style.color = "#ef4444";
      span.textContent = "Not Configured";
    }

    statusEl.appendChild(icon);
    statusEl.appendChild(span);
  }

  updateConfigUI() {
    if (this.config.token) {
      document.getElementById("github-token").value = this.config.token;
    }
    if (this.config.owner) {
      document.getElementById("repo-owner").value = this.config.owner;
    }
    if (this.config.repo) {
      document.getElementById("repo-name").value = this.config.repo;
    }
    document.getElementById("auto-refresh").checked = this.config.autoRefresh;
  }

  startAutoRefresh() {
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer);
    }

    // Validate refresh interval to prevent rapid-fire API calls
    const interval = this.config.refreshInterval || 120000;
    if (interval < 10000) {
      console.warn(
        "⚠️ Refresh interval too short, minimum 10s required. Using default 2 minutes.",
      );
      this.config.refreshInterval = 120000;
    }

    this.refreshTimer = setInterval(() => {
      this.refreshData();
    }, this.config.refreshInterval);
  }

  async triggerWorkflow() {
    try {
      await this.githubAPI(
        `/repos/${this.config.owner}/${this.config.repo}/actions/workflows/infrastructure-deployment.yml/dispatches`,
        {
          method: "POST",
          body: JSON.stringify({
            ref: "main",
          }),
        },
      );

      this.showSuccess("Workflow triggered successfully");
      setTimeout(() => this.refreshData(), 5000);
    } catch (error) {
      this.showError("Failed to trigger workflow: " + error.message);
    }
  }

  async resetSuccessState() {
    try {
      await this.githubAPI(
        `/repos/${this.config.owner}/${this.config.repo}/actions/workflows/infrastructure-deployment.yml/dispatches`,
        {
          method: "POST",
          body: JSON.stringify({
            ref: "main",
            inputs: {
              reset_success_state: "true",
            },
          }),
        },
      );

      this.showSuccess("Success state reset workflow triggered");
      setTimeout(() => this.refreshData(), 5000);
    } catch (error) {
      this.showError("Failed to reset success state: " + error.message);
    }
  }

  exportData() {
    const data = {
      timestamp: new Date().toISOString(),
      config: { ...this.config, token: "[REDACTED]" },
      lastUpdate: this.lastUpdate,
    };

    const blob = new Blob([JSON.stringify(data, null, 2)], {
      type: "application/json",
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `oracle-instance-dashboard-${Date.now()}.json`;
    a.click();
    URL.revokeObjectURL(url);

    this.showSuccess("Dashboard data exported");
  }

  viewLogs() {
    const url = `https://github.com/${this.config.owner}/${this.config.repo}/actions`;
    window.open(url, "_blank");
  }

  showSuccess(message) {
    this.showNotification(message, "success");
  }

  showError(message) {
    this.showNotification(message, "error");
  }

  showNotification(message, type) {
    // Simple notification system
    const notification = document.createElement("div");
    notification.className = `notification ${type}`;
    notification.textContent = message;
    notification.style.cssText = `
            position: fixed;
            top: 20px;
            right: 20px;
            padding: 12px 20px;
            border-radius: 6px;
            color: white;
            background: ${type === "success" ? "#10b981" : "#ef4444"};
            z-index: 1000;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
        `;

    document.body.appendChild(notification);

    setTimeout(() => {
      notification.remove();
    }, 5000);
  }

  // Cleanup method to prevent memory leaks
  cleanup() {
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = null;
    }
    if (this.offlineTimer) {
      clearInterval(this.offlineTimer);
      this.offlineTimer = null;
    }
  }
}

// Initialize dashboard when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
  new OracleInstanceDashboard()
})
