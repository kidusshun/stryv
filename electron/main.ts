import path from 'node:path';
import { BrowserWindow, Menu, Tray, app, ipcMain, nativeImage, screen } from 'electron';
import {
  closeDatabase,
  createCategory,
  createClassificationRule,
  getCategories,
  getClassificationRules,
  getDatabaseStatus,
  getTodayDashboard,
  initializeDatabase,
  startIntentSession,
  stopActiveIntentSession,
  setClassificationRuleEnabled,
  type CategoryInput,
  type ClassificationRuleInput,
  type IntentSessionInput,
} from './database';
import { getTrackerStatus, startTracker, stopTracker } from './tracker';

let mainWindow: BrowserWindow | null = null;
let tray: Tray | null = null;
let isQuitting = false;
let chromeHoverInterval: NodeJS.Timeout | null = null;
let isChromeHovered = false;

const isDev = Boolean(process.env.VITE_DEV_SERVER_URL);
const hasSingleInstanceLock = app.requestSingleInstanceLock();

if (!hasSingleInstanceLock) {
  app.quit();
}

function createMainWindow(): void {
  mainWindow = new BrowserWindow({
    title: 'Stryv',
    width: 1180,
    height: 760,
    minWidth: 900,
    minHeight: 620,
    frame: false,
    autoHideMenuBar: true,
    show: false,
    backgroundColor: '#070707',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  mainWindow.once('ready-to-show', () => {
    mainWindow?.show();
  });

  mainWindow.on('close', (event) => {
    if (!isQuitting) {
      event.preventDefault();
      mainWindow?.hide();
    }
  });

  mainWindow.on('blur', () => {
    setChromeHover(false);
  });

  if (isDev) {
    void mainWindow.loadURL(process.env.VITE_DEV_SERVER_URL as string);
  } else {
    void mainWindow.loadFile(path.join(__dirname, '..', 'dist', 'index.html'));
  }
}

function startChromeHoverWatcher(): void {
  if (chromeHoverInterval) {
    return;
  }

  chromeHoverInterval = setInterval(() => {
    if (!mainWindow || !mainWindow.isVisible() || mainWindow.isMinimized()) {
      setChromeHover(false);
      return;
    }

    const cursor = screen.getCursorScreenPoint();
    const bounds = mainWindow.getBounds();
    const isInsideWindow =
      cursor.x >= bounds.x &&
      cursor.x <= bounds.x + bounds.width &&
      cursor.y >= bounds.y &&
      cursor.y <= bounds.y + bounds.height;

    if (!isInsideWindow) {
      setChromeHover(false);
      return;
    }

    setChromeHover(cursor.y - bounds.y <= 56);
  }, 80);
}

function stopChromeHoverWatcher(): void {
  if (chromeHoverInterval) {
    clearInterval(chromeHoverInterval);
    chromeHoverInterval = null;
  }
}

function setChromeHover(nextValue: boolean): void {
  if (isChromeHovered === nextValue) {
    return;
  }

  isChromeHovered = nextValue;
  mainWindow?.webContents.send('window:chromeHoverChanged', isChromeHovered);
}

function createTray(): void {
  const icon = nativeImage.createFromDataURL(
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAN0lEQVR4AWMYVqD7z0AEYBxVSFUBI2CyAqMGjBoARcClc5gRI4ZhZGBg+M8ABiSODUCGAAAjzy8RdDJ1nQAAAABJRU5ErkJggg==',
  );

  tray = new Tray(icon);
  tray.setToolTip('Stryv');
  tray.setContextMenu(
    Menu.buildFromTemplate([
      { label: 'Open Dashboard', click: restoreMainWindow },
      { type: 'separator' },
      {
        label: 'Quit Stryv',
        click: () => {
          isQuitting = true;
          app.quit();
        },
      },
    ]),
  );

  tray.on('click', restoreMainWindow);
}

function restoreMainWindow(): void {
  if (!mainWindow) {
    createMainWindow();
  }

  mainWindow?.show();
  if (mainWindow?.isMinimized()) {
    mainWindow.restore();
  }
  mainWindow?.focus();
}

app.whenReady().then(() => {
  if (!hasSingleInstanceLock) {
    return;
  }

  initializeDatabase();
  Menu.setApplicationMenu(null);
  startTracker();
  createMainWindow();
  startChromeHoverWatcher();
  createTray();

  ipcMain.handle('app:getDatabaseStatus', () => getDatabaseStatus());
  ipcMain.handle('window:minimize', () => mainWindow?.minimize());
  ipcMain.handle('window:toggleMaximize', () => {
    if (!mainWindow) {
      return false;
    }

    if (mainWindow.isMaximized()) {
      mainWindow.unmaximize();
      return false;
    }

    mainWindow.maximize();
    return true;
  });
  ipcMain.handle('window:closeToTray', () => mainWindow?.hide());
  ipcMain.handle('tracking:getStatus', () => getTrackerStatus());
  ipcMain.handle('dashboard:getToday', () => getTodayDashboard());
  ipcMain.handle('categories:list', () => getCategories());
  ipcMain.handle('categories:create', (_event, input: CategoryInput) => createCategory(input));
  ipcMain.handle('rules:list', () => getClassificationRules());
  ipcMain.handle('rules:create', (_event, input: ClassificationRuleInput) => createClassificationRule(input));
  ipcMain.handle('rules:setEnabled', (_event, ruleId: number, isEnabled: boolean) =>
    setClassificationRuleEnabled(ruleId, isEnabled),
  );
  ipcMain.handle('intent:start', (_event, input: IntentSessionInput) => startIntentSession(input));
  ipcMain.handle('intent:stopActive', () => stopActiveIntentSession());

  app.on('activate', restoreMainWindow);
});

app.on('second-instance', restoreMainWindow);

app.on('before-quit', () => {
  isQuitting = true;
  stopTracker();
  stopChromeHoverWatcher();
  closeDatabase();
});

app.on('window-all-closed', () => {});
