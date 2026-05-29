import { BrowserWindow, powerMonitor } from 'electron';
import {
  getCurrentActivity,
  getActivityFingerprint,
  getTrackingSettings,
  recordActivityChange,
  stopCurrentSession,
  touchCurrentSession,
  type ActivitySampleInput,
  type CurrentActivity,
} from './database';

type ActiveWindowResult = {
  title: string;
  owner: {
    name: string;
    path: string;
  };
};

type TrackerStatus = {
  isRunning: boolean;
  pollIntervalSeconds: number;
  idleThresholdSeconds: number;
  current: CurrentActivity;
};

const browserNames = [
  'arc',
  'brave',
  'chrome',
  'chromium',
  'firefox',
  'google chrome',
  'microsoft edge',
  'mozilla firefox',
  'opera',
  'vivaldi',
  'zen',
  'zen browser',
];

const knownSiteNames = [
  'ChatGPT',
  'Claude',
  'Discord',
  'Figma',
  'GitHub',
  'Gmail',
  'Google Calendar',
  'Google Docs',
  'Google Drive',
  'Instagram',
  'Linear',
  'LinkedIn',
  'Notion',
  'Reddit',
  'Rize',
  'Slack',
  'TikTok',
  'Twitch',
  'X',
  'YouTube',
];

let interval: NodeJS.Timeout | null = null;
let lastActivityKey: string | null = null;
let isPolling = false;

export function startTracker(): void {
  if (interval) {
    return;
  }

  const settings = getTrackingSettings();
  void pollActiveWindow();
  interval = setInterval(() => {
    void pollActiveWindow();
  }, settings.pollIntervalSeconds * 1000);
}

export function stopTracker(): void {
  if (interval) {
    clearInterval(interval);
    interval = null;
  }

  stopCurrentSession(new Date().toISOString());
}

export function getTrackerStatus(): TrackerStatus {
  const settings = getTrackingSettings();

  return {
    isRunning: Boolean(interval),
    pollIntervalSeconds: settings.pollIntervalSeconds,
    idleThresholdSeconds: settings.idleThresholdSeconds,
    current: getCurrentActivity(),
  };
}

async function pollActiveWindow(): Promise<void> {
  if (isPolling) {
    return;
  }

  isPolling = true;

  try {
    const sample = await getActivitySample();
    const key = getActivityFingerprint(sample);

    if (key === lastActivityKey) {
      touchCurrentSession(sample.sampledAt);
    } else {
      recordActivityChange(sample, lastActivityKey === null);
      lastActivityKey = key;
    }

    notifyTrackingStatus();
  } catch (error) {
    console.error('Failed to poll active window:', error);
  } finally {
    isPolling = false;
  }
}

async function getActivitySample(): Promise<ActivitySampleInput> {
  const settings = getTrackingSettings();
  const sampledAt = new Date().toISOString();
  const isIdle = powerMonitor.getSystemIdleTime() >= settings.idleThresholdSeconds;

  if (isIdle) {
    return {
      sampledAt,
      appName: 'Break',
      executablePath: null,
      windowTitle: 'Break',
      isIdle: true,
    };
  }

  const activeWindow = await getActiveWindow();
  const normalizedActivity = normalizeActiveWindow(activeWindow);

  return {
    sampledAt,
    appName: normalizedActivity.appName,
    executablePath: normalizedActivity.executablePath,
    windowTitle: normalizedActivity.windowTitle,
    isIdle: false,
  };
}

function normalizeActiveWindow(activeWindow: ActiveWindowResult | undefined): Pick<
  ActivitySampleInput,
  'appName' | 'executablePath' | 'windowTitle'
> {
  const ownerName = activeWindow?.owner.name?.trim() || 'Unknown App';
  const executablePath = activeWindow?.owner.path?.trim() || null;
  const windowTitle = activeWindow?.title?.trim() || null;

  if (!isBrowserWindow(ownerName, executablePath)) {
    return {
      appName: ownerName,
      executablePath,
      windowTitle,
    };
  }

  return {
    appName: getWebsiteActivityName(windowTitle, ownerName),
    executablePath,
    windowTitle,
  };
}

function isBrowserWindow(ownerName: string, executablePath: string | null): boolean {
  const target = `${ownerName} ${executablePath ?? ''}`.toLowerCase();

  return browserNames.some((browserName) => target.includes(browserName));
}

function getWebsiteActivityName(windowTitle: string | null, browserName: string): string {
  if (!windowTitle) {
    return browserName;
  }

  const pageTitle = stripBrowserTitleSuffix(windowTitle);
  const knownSite = knownSiteNames.find((siteName) =>
    new RegExp(`(^|\\b)${escapeRegExp(siteName)}(\\b|$)`, 'i').test(pageTitle),
  );

  if (knownSite) {
    return knownSite;
  }

  const titleParts = pageTitle
    .split(/\s(?:[|—–-])\s/g)
    .map((part) => part.trim())
    .filter(Boolean);
  const inferredSite = titleParts.length > 1 ? titleParts[titleParts.length - 1] : pageTitle;

  return normalizeWebsiteName(inferredSite) || pageTitle || browserName;
}

function stripBrowserTitleSuffix(windowTitle: string): string {
  const browserSuffixes = browserNames
    .map((browserName) => escapeRegExp(browserName))
    .join('|');
  const suffixPattern = new RegExp(`\\s(?:[—–-])\\s(?:${browserSuffixes})$`, 'i');

  return windowTitle.replace(suffixPattern, '').trim();
}

function normalizeWebsiteName(value: string): string {
  return value
    .replace(/^\(\d+\)\s*/, '')
    .replace(/\s+\(.+\)$/, '')
    .trim();
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

async function getActiveWindow(): Promise<ActiveWindowResult | undefined> {
  const getWindows = (await import('get-windows')) as {
    activeWindow: () => Promise<ActiveWindowResult | undefined>;
  };

  return getWindows.activeWindow();
}

function notifyTrackingStatus(): void {
  const status = getTrackerStatus();

  for (const window of BrowserWindow.getAllWindows()) {
    window.webContents.send('tracking:statusChanged', status);
  }
}
