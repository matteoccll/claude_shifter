// Processo main di Electron — solo il guscio della finestra.
// Tutta la logica sta nel renderer (renderer/), che è apribile anche in un
// browser normale grazie al mockBroker. Vedi DECISIONI-FRONTEND.md.
const { app, BrowserWindow } = require('electron');
const path = require('path');

function createWindow() {
  const win = new BrowserWindow({
    width: 560,
    height: 820,
    resizable: true,
    backgroundColor: '#1a1206',
    title: 'MODEL AND FURIOUS',
    webPreferences: {
      // Il renderer non usa Node: gira contro il mockBroker (o, in futuro, un
      // broker esposto via preload/IPC). Niente nodeIntegration.
      contextIsolation: true
    }
  });

  win.setMenuBarVisibility(false);
  win.loadFile(path.join(__dirname, 'renderer', 'index.html'));
}

app.whenReady().then(() => {
  createWindow();
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
