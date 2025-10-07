# Azure App Service (Linux) + Key Vault + App Insights — Node/Express
## Prerequisites

- Azure CLI 2.62+  
- Node.js 18 or 20  
- `zip` (to package), `jq` (optional for pretty JSON)
- You’re logged into the correct Azure subscription:

```bash
az account show --query name -o tsv

## Verify App Settings

Run this once your deployment completes to confirm that your Key Vault and Application Insights values are wired correctly:

```bash
RG=playground-rg-central
APP=playground-web-lnx10930

az webapp config appsettings list -g $RG -n $APP \
  --query "[?name=='STORAGE_CONN' || name=='APPINSIGHTS_CONNECTIONSTRING'].[name,value]" -o table
```

Expected: both keys appear, with `STORAGE_CONN` masked.

## Smoke Test + Telemetry Check

After deploying, confirm the app responds and telemetry flows to Application Insights:

```bash
curl -s https://playground-web-lnx10930.azurewebsites.net/health
curl -s https://playground-web-lnx10930.azurewebsites.net/diag | jq .
az monitor app-insights query -g $RG -a playground-webapp-sblset4cw77mo-ai \
  --analytics-query "customEvents | where name in ('ManualStartupTest','DiagPing') | top 5 by timestamp desc" -o table
```

Expected:
- `/health` returns **OK**
- `/diag` returns `{ "ok": true, "sent": "DiagPing" }`
- The App Insights query shows recent `DiagPing` entries.

**What this deploys**
- Linux App Service (NODE|20-lts), `npm start`, binds `0.0.0.0`
- HTTPS-only, TLS 1.2, HTTP/2, Always On
- Health probe at `/health`
- Secret via Key Vault reference → `STORAGE_CONN` (masked in `/`)
- Application Insights wired (SDK + `/diag` custom event)

**Endpoints**
- `/health` → 200 OK (platform probe)
- `/`      → JSON { ok, storageConnMasked }
- `/diag`  → emits `DiagPing` event to App Insights and returns JSON

**Deploy (zip)**
```bash
cd webapp
zip -r ../app.zip .
az webapp deploy -g playground-rg-central -n playground-web-lnx10930 --type zip --src-path ../app.zip
