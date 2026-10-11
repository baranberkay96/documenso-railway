# Documenso v2 Document Signing — Railway template spec

## Listing

| Field | Value |
|---|---|
| Name | **Documenso v2 Document Signing** (version label `v2` = Documenso major version; Documenso tags releases `v2.x.y`) |
| Description | Send and sign PDFs with audit trails. Self-hosted DocuSign alternative. (71 chars, unchanged from LISTINGS_ROUND2.md) |
| Category | Other |
| Tags | documenso, e-signature, document-signing, docusign-alternative, pdf, postgres |
| User input at deploy | **`DOCUMENSO_ADMIN_EMAIL`** (first administrator). Everything else is generated. Optional later: Resend or SMTP, Google sign-in. |

## Base market template

- **`DjrRRX` "documenso"** (136 active / 48 recent projects; the template Documenso's own Railway docs link to) — chosen as base for the service shape (one app service + Postgres, generated `NEXTAUTH_SECRET` and encryption keys, `/api/health`).
  Fixed: builds the whole Documenso monorepo from `main` on every deploy (5–10 min builds, unpinned), **no signing certificate at all** (documents cannot be sealed), `postgres-ssl:latest` with `DATABASE_URL` on the public TCP proxy, SMTP-only mail (blocked on Railway Hobby), no job queue, no admin bootstrap, no storage choice.
- **`documenso-signing`** (20 active) — pinned `v2.9.0` image and Postgres in the database transport. Its signing setup expects the user to paste their own base64 `.p12`; the placeholder default is a password-protected bundle that the template's randomly generated passphrase cannot open (checked with `openssl pkcs12`), so sealing fails until the user generates a certificate by hand. Not reused.
- **`documenso`** (20 active) — builds a third-party fork with `prisma migrate dev` and seed at build time. Not reused.
- No `_upstream` repos exist for this app. Market templates carry no license → reference only.

## Pinned versions

| Service | Image / source | Tag | Release date | Checked |
|---|---|---|---|---|
| Documenso | `services/documenso` → `FROM documenso/documenso` | `v2.20.0` (= `latest` digest `sha256:05d2ede9fb87b…`) | 2026-10-08 | 2026-10-11 |
| ↳ su-exec | Alpine 3.23 package | distro | — | 2026-10-11 |
| Postgres | `ghcr.io/railwayapp-templates/postgres-ssl` | `18` | Railway base | 2026-10-11 |
| Redis | `redis` | `8.2` | Railway base | 2026-10-11 |
| Gotenberg | `gotenberg/gotenberg` | `8.37.0-libreoffice` | 2026-09-11 | 2026-10-11 |

**Upgrade:** change `DOCUMENSO_VERSION` in `services/documenso/Dockerfile`, back up Postgres, redeploy. The pre-deploy step applies Prisma migrations before the new version starts; a failed migration stops the deploy and the old version keeps running.

## Architecture

```
Signers / senders ──HTTPS──▶ Documenso (React Router + Hono, :3000, public)
                               │  pre-deploy: prisma migrate deploy (waits for Postgres)
                               │  boot (root): create/verify .p12 on volume → drop to uid 1001
                               │  background: first-admin bootstrap
                               ├─▶ Postgres 18   (documents metadata, audit logs)
                               ├─▶ Redis 8.2     (BullMQ: e-mails, sealing, webhooks, reminders)
                               ├─▶ Bucket        (PDFs, server-side S3 calls)
                               └─▶ Gotenberg 8   (DOCX → PDF via LibreOffice, private, basic auth)
volume /opt/documenso: cert.p12 (self-signed signing certificate, passphrase-protected)
```

### Deviations from upstream compose (and why)

- **Signing certificate generated at first boot.** Upstream mounts a `.p12` you create by hand. The thin image runs a root entrypoint that, if the volume is empty, creates a self-signed RSA-3072 certificate (`openssl req -x509` + `openssl pkcs12 -export` with `NEXT_PRIVATE_SIGNING_PASSPHRASE`, as in Documenso's local-certificate docs), stores it as `cert.p12` (mode 0400, owner uid 1001) on the volume, verifies it opens with the passphrase, then drops to the image's `nodejs` user with `su-exec`. Verified locally: Documenso's `P12Signer` loads the OpenSSL 3 (PBES2/AES-256) bundle, `/api/certificate-status` reports `isAvailable: true`, `/api/health` reports `certificate: ok`. A CA-issued certificate can replace the file or be supplied as `NEXT_PRIVATE_SIGNING_LOCAL_FILE_CONTENTS`.
- **Migrations in pre-deploy.** Upstream's `start.sh` migrates at container start; here `documenso-migrate.sh` runs `prisma migrate deploy` as the pre-deploy command with retries (up to 5 min) while Postgres starts. `start.sh` still runs and finds nothing to apply.
- **BullMQ + Redis instead of the default local job provider.** Documenso's docs call the default provider unsuitable for production and recommend BullMQ for self-hosting; Redis runs with `noeviction` (BullMQ requirement). The BullMQ worker runs inside the app process (upstream design), so there is no separate worker service.
- **Gotenberg added** (`gotenberg:8-libreoffice` with the flags from Documenso's document-conversion guide). It enables `.docx` uploads; without it Documenso accepts PDF only. Microsoft core fonts are not added (EULA), so Word layouts use metric-compatible substitutes.
- **Railway Bucket for documents** (`NEXT_PUBLIC_UPLOAD_TRANSPORT=s3`) instead of upstream's default of base64 blobs in Postgres. Uploads and downloads go through the server (`uploadS3File`, `getFileServerSide`), so the bucket needs no CORS rule. Switch back with `NEXT_PUBLIC_UPLOAD_TRANSPORT=database`.
- **E-mail transport auto-selection.** Upstream needs `NEXT_PRIVATE_SMTP_TRANSPORT` set explicitly and throws at start-up if it is `resend` without a key. The entrypoint picks `resend` when a Resend key is present, otherwise `smtp-auth`, so the app always boots.
- **First-admin bootstrap.** Documenso has no admin bootstrap: every sign-up needs e-mail verification and admins are made in SQL. `bootstrap-admin.cjs` creates `DOCUMENSO_ADMIN_EMAIL` through Documenso's own sign-up endpoint (sending the required `Origin` header for its CSRF guard), then marks it verified and adds the `ADMIN` role via Prisma. It never modifies an existing account unless it is the only (non-system) user — the retry case. Verified locally: sign-in with the generated password returns a session, `/admin` opens, a restart logs `already exists; nothing to do`.

## Services

All services are created together from the template; references resolve at deploy time. Empty values are optional.

### Documenso

- **Source:** repo `baranberkay96/documenso-railway`, root directory `/services/documenso` (Dockerfile build)
- **Start command:** image default
- **Pre-deploy command:** `/usr/local/bin/documenso-migrate.sh` (timeout 600 s)
- **Healthcheck:** `/api/health` (timeout 900 s)
- **Public domain:** yes → target port `3000`
- **TCP proxy:** none
- **Volume:** `/opt/documenso`
- **Restart policy:** ON_FAILURE (max 10 retries)
- **Replicas:** 1

| Variable | Value | Description |
|---|---|---|
| `PORT` | `3000` | Port the Documenso server listens on; Railway routes traffic and healthchecks here. |
| `NEXT_PUBLIC_WEBAPP_URL` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` | Public URL (links in e-mails, signing pages, CSRF origin). Change it when you add a custom domain. |
| `NEXTAUTH_SECRET` | `${{secret(48)}}` | Signs sessions and CSRF cookies. Changing it signs everyone out. |
| `NEXT_PRIVATE_ENCRYPTION_KEY` | `${{secret(48)}}` | Primary key (min. 32 characters) for encrypted fields such as 2FA secrets and API tokens. Never change it after first boot. |
| `NEXT_PRIVATE_ENCRYPTION_SECONDARY_KEY` | `${{secret(48)}}` | Secondary encryption key (min. 32 characters). Never change it after first boot. |
| `NEXT_PRIVATE_DATABASE_URL` | `${{Postgres.DATABASE_URL}}` | Postgres connection string (private network). |
| `NEXT_PRIVATE_DIRECT_DATABASE_URL` | `${{Postgres.DATABASE_URL}}` | Direct connection used by Prisma migrations (same as above without a pooler). |
| `NEXT_PRIVATE_JOBS_PROVIDER` | `bullmq` | Background jobs (e-mails, sealing, webhooks, reminders) on BullMQ + Redis, upstream's recommended self-hosted production provider. |
| `NEXT_PRIVATE_REDIS_URL` | `${{Redis.REDIS_URL}}?family=0` | Redis for the BullMQ job queue. family=0 lets ioredis use IPv4 or IPv6 on the private network. |
| `NEXT_PRIVATE_REDIS_PREFIX` | `documenso` | Key prefix for the job queues. |
| `NEXT_PRIVATE_SIGNING_TRANSPORT` | `local` | Sign with a local .p12 certificate (created on the volume at first boot). |
| `NEXT_PRIVATE_SIGNING_PASSPHRASE` | `${{secret(32)}}` | Passphrase protecting the signing certificate. The certificate on the volume only opens with this value: do not change it after first boot. |
| `NEXT_PRIVATE_SIGNING_LOCAL_FILE_PATH` | `/opt/documenso/cert.p12` | Certificate path on the volume. Replace the file (or set NEXT_PRIVATE_SIGNING_LOCAL_FILE_CONTENTS to a base64 .p12) to use a CA-issued certificate. |
| `SIGNING_CERT_COMMON_NAME` | `${{RAILWAY_PUBLIC_DOMAIN}}` | Common name of the self-signed certificate created at first boot (shown in PDF signature panels). |
| `SIGNING_CERT_ORGANIZATION` | `Documenso Self-Hosted` | Organization name in the self-signed certificate. Set your company name before the first deploy. |
| `SIGNING_CERT_DAYS` | `3650` | Validity of the self-signed certificate in days. |
| `NEXT_PUBLIC_UPLOAD_TRANSPORT` | `s3` | Store documents in the Railway Bucket (s3). Set to database to keep them in Postgres instead. |
| `NEXT_PRIVATE_UPLOAD_ENDPOINT` | `${{Bucket.ENDPOINT}}` | S3 endpoint (Railway Bucket). |
| `NEXT_PRIVATE_UPLOAD_FORCE_PATH_STYLE` | `false` | Railway Buckets use virtual-hosted URLs; set true only for a legacy bucket that requires path-style. |
| `NEXT_PRIVATE_UPLOAD_REGION` | `${{Bucket.REGION}}` | Bucket region. |
| `NEXT_PRIVATE_UPLOAD_BUCKET` | `${{Bucket.BUCKET}}` | Bucket name. |
| `NEXT_PRIVATE_UPLOAD_ACCESS_KEY_ID` | `${{Bucket.ACCESS_KEY_ID}}` | Bucket access key. |
| `NEXT_PRIVATE_UPLOAD_SECRET_ACCESS_KEY` | `${{Bucket.SECRET_ACCESS_KEY}}` | Bucket secret key. |
| `NEXT_PUBLIC_DOCUMENT_SIZE_UPLOAD_LIMIT` | `10` | Maximum document upload size in MB. |
| `NEXT_PRIVATE_DOCUMENT_CONVERSION_URL` | `http://${{Gotenberg.RAILWAY_PRIVATE_DOMAIN}}:3000` | Gotenberg service that converts uploaded .docx files to PDF (private network). |
| `NEXT_PRIVATE_DOCUMENT_CONVERSION_USERNAME` | `${{Gotenberg.GOTENBERG_API_BASIC_AUTH_USERNAME}}` | Shared with Gotenberg: references its basic-auth user (edit it there). |
| `NEXT_PRIVATE_DOCUMENT_CONVERSION_PASSWORD` | `${{Gotenberg.GOTENBERG_API_BASIC_AUTH_PASSWORD}}` | Shared with Gotenberg: references its basic-auth password (edit it there). |
| `NEXT_PRIVATE_SMTP_TRANSPORT` | *(empty)* | E-mail transport. Empty = automatic: resend when NEXT_PRIVATE_RESEND_API_KEY is set, otherwise smtp-auth. Also accepts smtp-api and mailchannels. |
| `NEXT_PRIVATE_RESEND_API_KEY` | *(empty)* | Resend API key (HTTP e-mail API, works on every Railway plan). Recommended way to send signing requests. |
| `NEXT_PRIVATE_SMTP_FROM_NAME` | `Documenso` | Sender display name for e-mails. |
| `NEXT_PRIVATE_SMTP_FROM_ADDRESS` | *(empty)* | Sender address, e.g. sign@yourcompany.com (must be a domain verified with your e-mail provider). |
| `NEXT_PRIVATE_SMTP_HOST` | *(empty)* | SMTP host (outbound SMTP needs Railway Pro). Optional. |
| `NEXT_PRIVATE_SMTP_PORT` | `587` | SMTP port (587 STARTTLS, 465 TLS). |
| `NEXT_PRIVATE_SMTP_USERNAME` | *(empty)* | SMTP username. Optional. |
| `NEXT_PRIVATE_SMTP_PASSWORD` | *(empty)* | SMTP password. Optional. |
| `NEXT_PRIVATE_SMTP_SECURE` | *(empty)* | Set true for implicit TLS (port 465). Optional. |
| `NEXT_PUBLIC_DISABLE_SIGNUP` | `false` | Set true to disable all new sign-ups once your team is in (the admin account is created by the bootstrap). |
| `NEXT_PRIVATE_ALLOWED_SIGNUP_DOMAINS` | *(empty)* | Comma-separated e-mail domains allowed to sign up, e.g. yourcompany.com. Empty = any domain. |
| `NEXT_PRIVATE_GOOGLE_CLIENT_ID` | *(empty)* | Optional Google OAuth client ID for 'Sign in with Google'. |
| `NEXT_PRIVATE_GOOGLE_CLIENT_SECRET` | *(empty)* | Optional Google OAuth client secret. |
| `DOCUMENSO_DISABLE_TELEMETRY` | `true` | Opt out of Documenso's anonymous instance telemetry (version and installation ID). Set false to share it. |
| `DOCUMENSO_ADMIN_EMAIL` | *(empty)* | E-mail of the first administrator. The template creates this account (verified, ADMIN role) on first boot so you can sign in without an e-mail provider. **Required input.** |
| `DOCUMENSO_ADMIN_PASSWORD` | `${{secret(32)}}` | Password of the first administrator (used once at creation; change it in your profile afterwards). |
| `DOCUMENSO_ADMIN_NAME` | `Administrator` | Display name of the first administrator. |

### Postgres

- **Source:** Docker image `ghcr.io/railwayapp-templates/postgres-ssl:18`
- **Start command:** image default
- **Healthcheck:** none
- **Public domain:** no (private network only)
- **TCP proxy:** none
- **Volume:** `/var/lib/postgresql/data`
- **Restart policy:** ON_FAILURE (max 10 retries)
- **Replicas:** 1

| Variable | Value | Description |
|---|---|---|
| `PGDATA` | `/var/lib/postgresql/data/pgdata` | Location where the database will be initialized. |
| `PGHOST` | `${{RAILWAY_PRIVATE_DOMAIN}}` | Railway Private Domain Name. |
| `PGPORT` | `5432` | Port to connect to Postgres. |
| `PGUSER` | `${{ POSTGRES_USER }}` | Required variable for Data panel. |
| `PGDATABASE` | `${{POSTGRES_DB}}` | Required variable for the data panel. |
| `PGPASSWORD` | `${{POSTGRES_PASSWORD}}` | Required variable for Data panel. |
| `POSTGRES_DB` | `railway` | Default database created when image is started. |
| `DATABASE_URL` | `postgresql://${{PGUSER}}:${{POSTGRES_PASSWORD}}@${{RAILWAY_PRIVATE_DOMAIN}}:5432/${{PGDATABASE}}` | URL to connect to Postgres database. |
| `POSTGRES_USER` | `postgres` | User to connect to Postgres DB. |
| `SSL_CERT_DAYS` | `820` | SSL certificate expiry in days. |
| `POSTGRES_PASSWORD` | `${{ secret(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ") }}` | Password to connect to DB. |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `60` | Allow Postgres to cleanly shut down. |

### Redis

- **Source:** Docker image `redis:8.2`
- **Start command:** `/bin/sh -c "rm -rf $RAILWAY_VOLUME_MOUNT_PATH/lost+found/ && exec docker-entrypoint.sh redis-server --requirepass $REDIS_PASSWORD --save 60 1 --dir $RAILWAY_VOLUME_MOUNT_PATH --maxmemory-policy noeviction"`
- **Healthcheck:** none
- **Public domain:** no (private network only)
- **TCP proxy:** none
- **Volume:** `/data`
- **Restart policy:** ON_FAILURE (max 10 retries)
- **Replicas:** 1

| Variable | Value | Description |
|---|---|---|
| `REDISHOST` | `${{RAILWAY_PRIVATE_DOMAIN}}` | Private network hostname of the Redis service, only resolvable from services in the same environment. |
| `REDISPORT` | `6379` | Port that Redis listens on. |
| `REDISUSER` | `default` | Username for authenticating with Redis. |
| `REDIS_URL` | `redis://${{ REDISUSER }}:${{ REDIS_PASSWORD }}@${{ REDISHOST }}:${{ REDISPORT }}` | Connection string for connecting to Redis using the private network. |
| `REDISPASSWORD` | `${{REDIS_PASSWORD}}` | Alias of REDIS_PASSWORD for clients that expect the unseparated name. |
| `REDIS_PASSWORD` | `${{ secret(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ") }}` | Randomly generated password for authenticating with Redis. |

### Gotenberg

- **Source:** Docker image `gotenberg/gotenberg:8.37.0-libreoffice`
- **Start command:** `gotenberg --api-enable-basic-auth --libreoffice-deny-private-ips --api-timeout=500s --libreoffice-auto-start --libreoffice-start-timeout=300s --pdfengines-disable-routes --webhook-disable`
- **Healthcheck:** `/health` (timeout 300 s)
- **Public domain:** no (private network only)
- **TCP proxy:** none
- **Volume:** none
- **Restart policy:** ON_FAILURE (max 10 retries)
- **Replicas:** 1

| Variable | Value | Description |
|---|---|---|
| `PORT` | `3000` | Port Gotenberg listens on ([::], dual-stack); used for the healthcheck. |
| `GOTENBERG_API_BASIC_AUTH_USERNAME` | `documenso` | Basic-auth user Documenso uses for conversions. |
| `GOTENBERG_API_BASIC_AUTH_PASSWORD` | `${{secret(32)}}` | Basic-auth password Documenso uses for conversions. |

### Bucket (Railway Bucket)

Create a Bucket named `Bucket` (any region). Documenso references `BUCKET`, `ENDPOINT`, `REGION`, `ACCESS_KEY_ID` and `SECRET_ACCESS_KEY` from it.


## Improvements over market templates

| # | Change | Why |
|---|---|---|
| 1 | Pinned official image `v2.20.0` + thin layer (leader: builds `main` from source) | Reproducible, ~1 min builds instead of 5–10 min monorepo builds. |
| 2 | Unique self-signed signing certificate created on a volume at first boot | The leader has no certificate and the other templates need a hand-made `.p12`, so documents cannot be sealed out of the box. |
| 3 | Migrations in pre-deploy with a Postgres wait | No crash-loop on a cold deploy; a failed upgrade keeps the old version running. |
| 4 | BullMQ + Redis job queue | Upstream's production recommendation; retries and a job dashboard (`/api/jobs/board`, admins only). |
| 5 | First admin created and verified automatically | Sign in immediately without SMTP; admin panel available. |
| 6 | Resend (HTTP API) supported and auto-selected | Railway Hobby blocks outbound SMTP. |
| 7 | Gotenberg for DOCX uploads | Feature that is otherwise disabled. |
| 8 | Railway Bucket for documents | Keeps Postgres small and backups fast. |
| 9 | Railway base Postgres 18 on the private network, telemetry opt-out, signup domain restriction variables | Standard Railway services, no public database proxy, privacy-friendly defaults. |

## First login

1. Open the public URL and sign in with `DOCUMENSO_ADMIN_EMAIL` and the password from the **Documenso** service variable `DOCUMENSO_ADMIN_PASSWORD` (the deploy log shows `[bootstrap-admin] … is verified and has the ADMIN role`). Change the password under your profile.
2. Upload a PDF (or a .docx), add recipients and fields, and send. Without an e-mail provider, use "copy signing link" for each recipient; with Resend set `NEXT_PRIVATE_RESEND_API_KEY` and `NEXT_PRIVATE_SMTP_FROM_ADDRESS` (a verified domain) and redeploy.
3. Restrict sign-ups with `NEXT_PRIVATE_ALLOWED_SIGNUP_DOMAINS`, or set `NEXT_PUBLIC_DISABLE_SIGNUP=true` once your team has accounts.
4. Custom domain: add it to the service and update `NEXT_PUBLIC_WEBAPP_URL` (also used as CSRF origin), then redeploy.

## Scaling

- **Documenso:** has a volume (certificate), so one replica; scale vertically. For several replicas, provide the certificate as `NEXT_PRIVATE_SIGNING_LOCAL_FILE_CONTENTS`, remove the volume and raise replicas — BullMQ distributes jobs across instances.
- **Gotenberg:** raise memory for large Word files; conversions time out after 30 s by default (`NEXT_PRIVATE_DOCUMENT_CONVERSION_TIMEOUT_MS`).
- **Postgres:** vertical; HA conversion available in Railway.

## Resource estimate

Railway prices: RAM $10/GB-month, vCPU $20/vCPU-month, volume $0.15/GB-month, Bucket $0.015/GB-month. Idle figures measured locally (2026-10-11).

| Service | Idle RAM | Idle CPU | Typical RAM | Typical CPU |
|---|---|---|---|---|
| Documenso | 380–470 MB | 0.01 vCPU | 600 MB | 0.08 vCPU |
| Postgres | 130 MB | 0.01 vCPU | 250 MB | 0.03 vCPU |
| Redis | 15 MB | <0.01 vCPU | 30 MB | 0.01 vCPU |
| Gotenberg | 95 MB (LibreOffice started) | <0.01 vCPU | 300 MB | 0.03 vCPU |
| **Total** | **≈0.7 GB** | **≈0.03 vCPU** | **≈1.2 GB** | **≈0.15 vCPU** |

- **Idle:** ≈ $7 RAM + $0.6 CPU + $0.2 volumes ≈ **$8/month**.
- **Typical (team sending a few hundred documents/month):** ≈ $12 RAM + $3 CPU + $0.5 volumes and bucket ≈ **$16/month**.
- **Minimum plan:** Hobby (four services; Trial's 1 GB/service fits, but Trial credit does not cover a month).

## Verification checklist

- [ ] **Documenso** pre-deploy log ends with `[documenso-migrate] database is up to date`.
- [ ] Boot log: `creating a self-signed signing certificate …`, `signing certificate OK`, then healthy on `/api/health` (`database: ok`, `certificate: ok`).
- [ ] Log line `[bootstrap-admin] <email> is verified and has the ADMIN role`; sign in; `/admin` opens.
- [ ] Upload a PDF, add yourself as signer, sign via the copied link; the completed PDF downloads and shows a digital signature (self-signed → "validity unknown" in Acrobat is expected).
- [ ] Upload a .docx → converted to PDF (Gotenberg logs a request).
- [ ] Objects appear in the Bucket; redeploy → certificate unchanged (no "creating" line), documents still open.
- [ ] Optional: set a Resend key → signing request e-mail arrives.

## Open questions

- **Bucket URL style:** Railway documents virtual-hosted URLs for new buckets, so `NEXT_PRIVATE_UPLOAD_FORCE_PATH_STYLE=false`. Not exercised against a real Railway Bucket here; if uploads fail with a signature/host error, set it to `true` (or use `database`).
- **Pre-deploy and the image entrypoint:** the entrypoint only runs boot actions for the default `sh start.sh` command; any other command (such as the pre-deploy script) runs unprivileged without side effects, so the step works whether or not Railway wraps it in the entrypoint.
- **Local functional test ran on the arm64 variant** of the same Dockerfile: the amd64 image builds cleanly, but under QEMU on Apple Silicon the Documenso server stops with `Illegal instruction` (emulation lacks a CPU feature a native module uses). This does not apply to Railway's x86-64 hosts but has not been observed there yet.
- **Self-signed certificates** are fine for internal and business use but show as "unknown signer" in Adobe Acrobat; organisations that need trusted signatures should supply a CA-issued `.p12`.
