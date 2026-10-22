# CQC app (optional, SPCS)

A React + FastAPI app that runs in Snowpark Container Services and reads the `SF_SOLUTIONS` CQC
schemas. Pages: Landing, Quality Command, Emerging Issues, Quality Alerts, Issue Detail,
Explainability, Impacted Fleet, Persona Views, Review Board (three-agent debate), Resolution
Tracker, Data Explorer, Data Readiness and Ask CQC (chat with `CUSTOMER_QUALITY_AGENT`), plus a
guided Story Mode for the LX-950 anchor defect.

**Not available on trial accounts:** it needs a compute pool and an image repository.

## Prerequisites

- The core solution is installed (`scripts/setup.sql`, `scripts/data.sql`, `scripts/pipeline.sql`)
- Docker, and the Snowflake CLI (`snow`) with a connection that uses `ACCOUNTADMIN`

## Deploy

1. Create the image repository and compute pool:

   ```bash
   snow sql -f app/setup_app.sql --enable-templating NONE
   ```

2. Build and push the image (`repository_url` comes from `SHOW IMAGE REPOSITORIES` in step 1;
   build from the `app/` directory, which the Dockerfile expects as its context):

   ```bash
   cd app
   snow spcs image-registry login
   docker build --platform linux/amd64 --provenance=false \
     -f deploy/Dockerfile -t <repository_url>/cqc:latest .
   docker push <repository_url>/cqc:latest
   ```

3. Create the service, then get the URL:

   ```bash
   snow sql -f app/create_service.sql --enable-templating NONE
   ```

   Open the `ingress_url` from the `SHOW ENDPOINTS` output and sign in with your Snowflake user.
   Endpoint provisioning can take a few minutes; re-run
   `SHOW ENDPOINTS IN SERVICE SF_SOLUTIONS.CQC_ML.CQC_APP_SERVICE;` until the URL appears.

## Updating the image

SPCS pins the image digest when the service spec is applied, so pushing a new `:latest` and
suspending/resuming the service does **not** pick it up. After pushing, re-apply the spec from
`app/create_service.sql`:

```sql
ALTER SERVICE SF_SOLUTIONS.CQC_ML.CQC_APP_SERVICE FROM SPECIFICATION $$
<the spec block from app/create_service.sql>
$$;
```

## Notes

- The container authenticates with the SPCS-provided OAuth token and queries through
  `SF_SOLUTIONS_WH`. The schema names come from `SCHEMA_PREFIX: CQC_` in the service spec.
- The Review Board calls `AI_COMPLETE` with `claude-sonnet-4-6` (set by `REVIEW_BOARD_MODEL`);
  change it in the spec if that model isn't available in your region.
- `scripts/teardown.sql` drops the service and the compute pool (`SF_SOLUTIONS_CQC_POOL`).
