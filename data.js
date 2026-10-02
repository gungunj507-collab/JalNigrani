// UI-safe empty state. Live data is loaded by supabase-data.js after authentication.
window.JalData = {
  mode: 'Loading', sourceNote: 'Loading your water-system data…',
  system: { availability: 0, flowRate: 0, dailyUsage: 0, estimatedAvailable: 0, status: 'No devices' },
  readings: [], alerts: [], devices: [], activity: [],
  trends: { labels: [], availability: [], flow: [], weeklyAvailability: [] },
  reports: [
    { period: 'Today', water: '0 L', flow: '0 L/min', availability: '—', change: '—' },
    { period: 'This week', water: '0 L', flow: '0 L/min', availability: '—', change: '—' },
    { period: 'This month', water: '0 L', flow: '0 L/min', availability: '—', change: '—' }
  ]
};
