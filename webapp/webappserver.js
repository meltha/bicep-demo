const appInsights = require('applicationinsights');
if (process.env.APPINSIGHTS_CONNECTIONSTRING) {
  appInsights
    .setup(process.env.APPINSIGHTS_CONNECTIONSTRING)
    .setAutoCollectRequests(true)
    .setAutoCollectDependencies(true)
    .setSendLiveMetrics(true)
    .start();
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
    message: 'App Service + Key Vault demo',
    storageConnMasked: storageConn.substring(0, 20) + '...'
  });
});

app.get('/health', (_req, res) => res.send('OK'));

app.listen(port, () => console.log(`Server listening on ${port}`));
