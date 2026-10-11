# NOTICE — Documenso v2 Document Signing

## Software deployed (not redistributed)

| Component | Source | License |
|---|---|---|
| Documenso | Docker image `documenso/documenso:v2.20.0` from https://github.com/documenso/documenso (used as base image of `services/documenso`) | AGPL-3.0 (repository `LICENSE`; enterprise features need a separate Documenso license key, not used here) |
| su-exec | Alpine package installed in `services/documenso` | MIT |
| PostgreSQL | Railway base image `ghcr.io/railwayapp-templates/postgres-ssl:18` | PostgreSQL License |
| Redis | `redis:8.2` (Railway base definition) | Redis 8 tri-license (RSALv2 / SSPLv1 / AGPLv3) |
| Gotenberg | `gotenberg/gotenberg:8.37.0-libreoffice` | MIT (Gotenberg); bundles LibreOffice (MPL-2.0) |

The template builds on these images; it does not modify their code. The files in `services/documenso/` (`Dockerfile`, `railway-entrypoint.sh`, `documenso-migrate.sh`, `bootstrap-admin.cjs`) are original work for this template.

## Upstream files checked (2026-10-11, tag `v2.20.0`)

- `docker/Dockerfile`, `docker/start.sh` — runtime user (uid 1001), working directory, start script, migration command, `HOSTNAME=0.0.0.0`.
- `docker/production/compose.yml` and `.env.example` — variables, defaults, transports (`NEXT_PRIVATE_JOBS_PROVIDER`, `NEXT_PRIVATE_UPLOAD_*`, `NEXT_PRIVATE_SMTP_TRANSPORT`, `NEXT_PRIVATE_DOCUMENT_CONVERSION_*`).
- `packages/signing/transports/local.ts` — certificate loading order (contents before path) and `P12Signer`.
- `packages/email/mailer.ts` — transport selection (resend without key throws at start-up).
- `packages/lib/universal/upload/*` and `providers/s3-provider.ts` — server-side S3 uploads/downloads.
- `packages/lib/jobs/client/bullmq.ts` — in-process BullMQ worker, ioredis connection.
- `packages/auth/server/routes/email-password.ts`, `types/email-password.ts`, `apps/remix/server/csrf-middleware.ts`, `packages/prisma/schema.prisma` — sign-up endpoint, password rules, CSRF origin check, `User.roles`/`emailVerified` (used by the admin bootstrap).
- Docs: `self-hosting/configuration/signing-certificate/local.mdx` (passphrase required), `configuration/background-jobs.mdx` (BullMQ recommended for self-hosted production), `configuration/advanced/document-conversion.mdx` (Gotenberg flags), `getting-started/quick-start.mdx` (admin role via SQL), `deployment/railway.mdx`.

## Reused material

- **Railway base definitions** `templates/_railway-base/postgres.json` and `redis.json` (this repository): copied as instructed by STANDARD.md; `--maxmemory-policy noeviction` appended to the Redis start command (BullMQ requirement).
- **Gotenberg command-line flags**: taken from Documenso's document-conversion guide (AGPL-3.0 documentation; flags are configuration values).
- **Market templates** `DjrRRX`, `documenso-signing`, `documenso` (Railway marketplace, no license): reviewed for structure and known problems only. No README text, descriptions or files were copied; all prose in this package is original.
- No `_upstream` repositories exist for this app.
