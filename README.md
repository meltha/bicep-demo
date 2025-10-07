# Azure App Service (Linux) + Key Vault + App Insights — Node/Express

## Project Overview

This project deploys a minimal **Node/Express** API to **Azure App Service (Linux, NODE|20-lts)** using Bicep templates and Azure CLI.

It demonstrates:
- **Key Vault integration** — securely pulling a connection string (no secrets in code)
- **Application Insights telemetry** — request tracking + `/diag` custom event
- **Operational hardening** — HTTPS-only, TLS 1.2, HTTP/2, Always On, `/health` probe
- **Idempotent infrastructure-as-code** — clean repeatable deploys with Bicep

---

## Quickstart

```bash
# Clone the repo
git clone https://github.com/meltha/bicep-demo.git
cd bicep-demo

# Set your resource names
RG=playground-rg-central
APP=playground-web-lnx10930
AI=playground-webapp-sblset4cw77mo-ai

# Package and deploy
cd webapp
zip -r ../app.zip .
az webapp deploy -g $RG -n $APP --type zip --src-path ../app.zip

# Smoke test
curl -s https://$APP.azurewebsites.net/health
curl -s https://$APP.azurewebsites.net/ | jq .
curl -s https://$APP.azurewebsites.net/diag | jq .
```

Expected:
- `/health` → **OK**
- `/` → JSON with masked Key Vault secret
- `/diag` → emits **DiagPing** to Application Insights

---

## Prerequisites

- Azure CLI 2.62+  
- Node.js 18 or 20  
- `zip` (for packaging), `jq` (for JSON output)
- Logged in and correct subscription selected:
  ```bash
  az account show --query name -o tsv
  ```

---

## Verify Configuration

Confirm Key Vault + App Insights wiring:

```bash
az webapp config appsettings list -g $RG -n $APP \
  --query "[?name=='STORAGE_CONN' || name=='APPINSIGHTS_CONNECTIONSTRING'].[name,value]" -o table
```

Expected: both keys appear, with `STORAGE_CONN` masked.

---

## Monitor Telemetry

Query Application Insights for recent custom events:

```bash
az monitor app-insights query -g $RG -a $AI \
  --analytics-query "customEvents | where name in ('ManualStartupTest','DiagPing') | top 5 by timestamp desc" -o table
```

Expected: `DiagPing` and request entries appear within a few minutes.

---

## Architecture Summary

| Component | Description |
|------------|-------------|
| **App Service (Linux)** | Runs Node/Express app under Node 20 LTS |
| **Key Vault** | Holds storage connection secret, referenced in configuration |
| **Application Insights** | Collects telemetry via SDK and REST |
| **Bicep Templates** | Declarative IaC provisioning |
| **Endpoints** | `/health`, `/`, `/diag` |

---

## Operational Settings

```bash
az webapp show -g $RG -n $APP \
  --query "{httpsOnly:httpsOnly,tls:siteConfig.minTlsVersion,alwaysOn:siteConfig.alwaysOn,health:siteConfig.healthCheckPath,runtime:siteConfig.linuxFxVersion}" -o json
```

Expected result:
```json
{
  "httpsOnly": true,
  "tls": "1.2",
  "alwaysOn": true,
  "health": "/health",
  "runtime": "NODE|20-lts"
}
```

---

## Future Work

**1) Staging slot (zero‑downtime deploys)**
- Create a slot that clones prod config, deploy to the slot, warm it up, then swap.
- Why: safer releases; quick rollback via swap.
```bash
az webapp deployment slot create -g $RG -n $APP --slot staging --configuration-source $APP
az webapp deploy -g $RG -n $APP --slot staging --type zip --src-path ../app.zip
curl -I https://$APP-staging.azurewebsites.net/health
az webapp deployment slot swap -g $RG -n $APP --slot staging --action swap
```

**2) GitHub Actions CI/CD (OIDC, no secrets)**
- Use federated credentials so Actions can deploy with `az webapp deploy` without storing publish profiles.
- Why: least-privilege, secretless pipeline, auditable.
```yaml
# .github/workflows/deploy.yml (sketch)
name: deploy
on: { push: { branches: [main] } }
jobs:
  webapp:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: actions/checkout@v4
      - uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      - run: |
          cd webapp
          zip -r ../app.zip .
          az webapp deploy -g $RG -n $APP --type zip --src-path ../app.zip
```

**3) Add a data tier (Azure SQL)**
- Provision Azure SQL + database in Bicep; store ADO connection string in Key Vault; app reads it via app settings (no secrets in code).
- Why: shows real PaaS stack: App Service + SQL + KV + Insights; aligns with AZ‑204 objectives.

---

## Cleanup

To avoid incurring charges, remove all deployed resources:

```bash
az group delete -n $RG --no-wait --yes
```

---

## License

MIT License © 2025 William Simpson

---
