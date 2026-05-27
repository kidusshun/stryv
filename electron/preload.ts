import { contextBridge, ipcRenderer } from 'electron';
import type {
  Category,
  CategoryInput,
  ClassificationRule,
  ClassificationRuleInput,
  DatabaseStatus,
  IntentSession,
  IntentSessionInput,
  TodayDashboard,
} from './database';
import type { getTrackerStatus } from './tracker';

type TrackerStatus = ReturnType<typeof getTrackerStatus>;

export type StryvApi = {
  getDatabaseStatus: () => Promise<DatabaseStatus>;
  getTodayDashboard: () => Promise<TodayDashboard>;
  getTrackerStatus: () => Promise<TrackerStatus>;
  getCategories: () => Promise<Category[]>;
  createCategory: (input: CategoryInput) => Promise<Category>;
  getClassificationRules: () => Promise<ClassificationRule[]>;
  createClassificationRule: (input: ClassificationRuleInput) => Promise<ClassificationRule>;
  setClassificationRuleEnabled: (ruleId: number, isEnabled: boolean) => Promise<ClassificationRule>;
  startIntentSession: (input: IntentSessionInput) => Promise<IntentSession>;
  stopActiveIntentSession: () => Promise<void>;
  minimizeWindow: () => Promise<void>;
  toggleMaximizeWindow: () => Promise<boolean>;
  closeWindowToTray: () => Promise<void>;
  onWindowChromeHoverChanged: (callback: (isHovered: boolean) => void) => () => void;
  onTrackerStatusChanged: (callback: (status: TrackerStatus) => void) => () => void;
};

const api: StryvApi = {
  getDatabaseStatus: () => ipcRenderer.invoke('app:getDatabaseStatus'),
  getTodayDashboard: () => ipcRenderer.invoke('dashboard:getToday'),
  getTrackerStatus: () => ipcRenderer.invoke('tracking:getStatus'),
  getCategories: () => ipcRenderer.invoke('categories:list'),
  createCategory: (input) => ipcRenderer.invoke('categories:create', input),
  getClassificationRules: () => ipcRenderer.invoke('rules:list'),
  createClassificationRule: (input) => ipcRenderer.invoke('rules:create', input),
  setClassificationRuleEnabled: (ruleId, isEnabled) => ipcRenderer.invoke('rules:setEnabled', ruleId, isEnabled),
  startIntentSession: (input) => ipcRenderer.invoke('intent:start', input),
  stopActiveIntentSession: () => ipcRenderer.invoke('intent:stopActive'),
  minimizeWindow: () => ipcRenderer.invoke('window:minimize'),
  toggleMaximizeWindow: () => ipcRenderer.invoke('window:toggleMaximize'),
  closeWindowToTray: () => ipcRenderer.invoke('window:closeToTray'),
  onWindowChromeHoverChanged: (callback) => {
    const listener = (_event: Electron.IpcRendererEvent, isHovered: boolean) => callback(isHovered);
    ipcRenderer.on('window:chromeHoverChanged', listener);

    return () => {
      ipcRenderer.removeListener('window:chromeHoverChanged', listener);
    };
  },
  onTrackerStatusChanged: (callback) => {
    const listener = (_event: Electron.IpcRendererEvent, status: TrackerStatus) => callback(status);
    ipcRenderer.on('tracking:statusChanged', listener);

    return () => {
      ipcRenderer.removeListener('tracking:statusChanged', listener);
    };
  },
};

contextBridge.exposeInMainWorld('stryv', api);
