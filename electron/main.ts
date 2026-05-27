import path from 'node:path';
import { BrowserWindow, Menu, Tray, app, ipcMain, nativeImage } from 'electron';
import { closeDatabase, getDatabaseStatus, getTodayDashboard, initializeDatabase } from './database';
import { getTrackerStatus, startTracker, stopTracker } from './tracker';

let mainWindow: BrowserWindow | null = null;
let tray: Tray | null = null;
let isQuitting = false;

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

  if (isDev) {
    void mainWindow.loadURL(process.env.VITE_DEV_SERVER_URL as string);
  } else {
    void mainWindow.loadFile(path.join(__dirname, '..', 'dist', 'index.html'));
  }
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

  app.on('activate', restoreMainWindow);
});

app.on('second-instance', restoreMainWindow);

app.on('before-quit', () => {
  isQuitting = true;
  stopTracker();
  closeDatabase();
});

app.on('window-all-closed', () => {});
