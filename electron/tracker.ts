import { BrowserWindow, powerMonitor } from 'electron';
import {
  getCurrentActivity,
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
    const key = getActivityKey(sample);

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
      appName: 'Idle',
      executablePath: null,
      windowTitle: 'Idle',
      isIdle: true,
    };
  }

  const activeWindow = await getActiveWindow();

  return {
    sampledAt,
    appName: activeWindow?.owner.name?.trim() || 'Unknown App',
    executablePath: activeWindow?.owner.path?.trim() || null,
    windowTitle: activeWindow?.title?.trim() || null,
    isIdle: false,
  };
}

async function getActiveWindow(): Promise<ActiveWindowResult | undefined> {
  const getWindows = (await import('get-windows')) as {
    activeWindow: () => Promise<ActiveWindowResult | undefined>;
  };

  return getWindows.activeWindow();
}

function getActivityKey(sample: ActivitySampleInput): string {
  return JSON.stringify({
    appName: sample.appName,
    executablePath: sample.executablePath,
    windowTitle: sample.windowTitle,
    isIdle: sample.isIdle,
  });
}

function notifyTrackingStatus(): void {
  const status = getTrackerStatus();

  for (const window of BrowserWindow.getAllWindows()) {
    window.webContents.send('tracking:statusChanged', status);
  }
}
