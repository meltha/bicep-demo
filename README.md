# Azure App Service (Linux) + Key Vault + App Insights — Node/Express

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
