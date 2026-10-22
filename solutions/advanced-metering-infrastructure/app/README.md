# AMI 2.0 operations dashboard (optional, SPCS)

A React + Express single-page app that runs in Snowpark Container Services and reads the
`SF_SOLUTIONS` AMI schemas. Pages: Home, Ingestion, Data Quality, Billing, TOU Charges,
Transformers, Map, Events, Anomalies, Edge Cases, Observability, Intelligence (chat with the
`AMI_INTELLIGENCE_AGENT` Cortex Agent) and Architecture.

**Not available on trial accounts:** it needs a compute pool, an image repository and an external
access integration.

## Prerequisites

- The core solution is installed (`scripts/setup.sql`, `scripts/data.sql`, `scripts/pipeline.sql`)
- Docker, and the Snowflake CLI (`snow`) with a connection that uses `ACCOUNTADMIN`

## Deploy

1. Create the image repository, compute pool and map-tile integration:

   ```bash
   snow sql -f app/setup_app.sql --enable-templating NONE
   ```

2. Build and push the image (`repository_url` comes from `SHOW IMAGE REPOSITORIES` in step 1):

   ```bash
   cd app
   snow spcs image-registry login
   docker build --platform linux/amd64 --provenance=false \
     -t <repository_url>/ami-dashboard:latest .
   docker push <repository_url>/ami-dashboard:latest
   ```

3. Create the service, then get the URL:

   ```bash
   snow sql -f app/create_service.sql --enable-templating NONE
   ```

   Open the `ingress_url` from the `SHOW ENDPOINTS` output and sign in with your Snowflake user.
   Endpoint provisioning can take a few minutes; re-run
   `SHOW ENDPOINTS IN SERVICE SF_SOLUTIONS.AMI_MART.AMI_DASHBOARD_SVC;` until the URL appears.

## Updating the image

SPCS pins the image digest when the service spec is applied, so pushing a new `:latest` and
suspending/resuming the service does **not** pick it up. After pushing, re-apply the spec:

```sql
ALTER SERVICE SF_SOLUTIONS.AMI_MART.AMI_DASHBOARD_SVC FROM SPECIFICATION $$
<contents of service-spec.yaml>
$$;
```

## Notes

- The container authenticates with the SPCS-provided OAuth token and queries through
  `SF_SOLUTIONS_WH`.
- The map uses OpenStreetMap tiles loaded by the viewer's browser. The browser can only load them
  because `tile.openstreetmap.org` is in the service's external access integration
  (`SF_SOLUTIONS_AMI_TILES_EAI`); keep that rule in sync if you change the tile provider.
- `scripts/teardown.sql` drops the service, the compute pool (`SF_SOLUTIONS_AMI_POOL`) and the
  integration.
