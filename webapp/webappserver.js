const appInsights = require('applicationinsights');

// Support both common env var names for AI connection strings
const aiConn =
  process.env.APPINSIGHTS_CONNECTIONSTRING ||
  process.env.APPLICATIONINSIGHTS_CONNECTION_STRING ||
  '';

if (aiConn) {
  appInsights
    .setup(aiConn)
    .setAutoCollectRequests(true)
    .setAutoCollectDependencies(true)
    .setSendLiveMetrics(true)
    .start();

  if (appInsights.defaultClient) {
    appInsights.defaultClient.config.samplingPercentage = 100;
  }

  // Emit one explicit event at startup so we can verify ingestion
  if (appInsights.defaultClient) {
    appInsights.defaultClient.trackEvent({ name: 'ManualStartupTest' });
    appInsights.defaultClient.flush();
    console.log('Telemetry test event sent.');
  }
}

const express = require('express');
const app = express();
const port = process.env.PORT || 8080;
const storageConn = process.env.STORAGE_CONN || '(not set)';

app.use((req, _res, next) => {
  console.log(new Date().toISOString(), req.method, req.url);
  next();
});

app.get('/', (_req, res) => {
  res.json({
    ok: true,
    env: 'staging',
    deployedAt: new Date().toISOString(),
    message: 'CI redeploy test 20:13:45Z',
    storageConnMasked: storageConn.substring(0, 20) + '...'
  });
});

app.get('/health', (_req, res) => res.send('OK'));

app.get('/diag', (_req, res) => {
  try {
    const ai = require('applicationinsights');
    if (ai.defaultClient) {
      ai.defaultClient.trackEvent({ name: 'DiagPing' });
      ai.defaultClient.flush();
      return res.json({ ok: true, sent: 'DiagPing' });
    }
    return res.status(500).json({ ok: false, error: 'no defaultClient' });
  } catch (e) {
    return res.status(500).json({ ok: false, error: String(e) });
  }
});

app.get('/diag/trace', (_req, res) => {
  try {
    if (appInsights.defaultClient) {
      appInsights.defaultClient.trackTrace({
        message: 'CI redeploy test 20:13:45Z',
        severity: 1,
        properties: { source: 'diag-endpoint' }
      });
      appInsights.defaultClient.flush();
      return res.json({ ok: true, sent: 'manual-trace' });
    }
    return res.status(500).json({ ok: false, error: 'no defaultClient' });
  } catch (e) {
    return res.status(500).json({ ok: false, error: String(e) });
  }
});

app.listen(port, '0.0.0.0', () => console.log(`Server listening on ${port}`));

process.on('uncaughtException', (err) => {
  console.error('Uncaught exception:', err);
  process.exit(1);
});

process.on('unhandledRejection', (reason) => {
  console.error('Unhandled promise rejection:', reason);
  process.exit(1);
});