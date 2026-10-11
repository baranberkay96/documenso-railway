# Deploy and Host Documenso with Railway

Documenso is an open-source document signing platform: upload a PDF or Word file, place fields, send it to signers, and receive a digitally sealed PDF with a full audit trail. This community template runs Documenso v2 on Railway with Postgres, a Redis job queue, DOCX conversion and its own signing certificate.

## About Hosting Documenso

Documenso is a single Node.js web app that needs Postgres, a background job system for e-mails, sealing and webhooks, file storage for documents, and an X.509 certificate to seal completed PDFs. The certificate is the step most self-hosters get stuck on. This template creates a unique self-signed certificate on a volume at first boot, runs migrations as a pre-deploy step, uses BullMQ on Redis for jobs, stores documents in a Railway Bucket, adds Gotenberg so .docx uploads work, and creates your first admin account so you can sign in before any e-mail provider is set up.

## Common Use Cases

- Sending contracts, NDAs and offer letters for signature without per-envelope fees
- Internal approvals and policy acknowledgements with a tamper-evident audit log
- Embedding signing flows into your own product through Documenso's API and webhooks
- Keeping signed documents and signer data in infrastructure you control

## Dependencies for Documenso Hosting

- Documenso (`documenso/documenso:v2.20.0` plus a thin Railway layer)
- PostgreSQL (Railway Postgres 18)
- Redis (BullMQ job queue)
- Gotenberg 8 with LibreOffice (DOCX to PDF)
- S3-compatible storage (Railway Bucket)
- Optional: a Resend account (or SMTP on Railway Pro) for e-mails

### Deployment Dependencies

- Documenso self-hosting docs: https://docs.documenso.com/docs/self-hosting
- Signing certificate guide: https://docs.documenso.com/docs/self-hosting/configuration/signing-certificate
- Documenso source and releases: https://github.com/documenso/documenso
- Gotenberg: https://gotenberg.dev
- Resend (e-mail API): https://resend.com
- Railway Buckets: https://docs.railway.com/storage-buckets

### Implementation Details

| Service | Image / source | Role |
|---|---|---|
| Documenso | `services/documenso` (from `documenso/documenso:v2.20.0`) | Web app and API; pre-deploy migrations; signing certificate on a volume; first-admin bootstrap |
| Postgres | `ghcr.io/railwayapp-templates/postgres-ssl:18` | Database (volume) |
| Redis | `redis:8.2` | BullMQ queue for e-mails, sealing, reminders and webhooks (`noeviction`) |
| Gotenberg | `gotenberg/gotenberg:8.37.0-libreoffice` | Converts uploaded .docx files to PDF (private, basic auth) |
| Bucket | Railway Bucket | Uploaded and signed documents |

**First login:** enter your e-mail in `DOCUMENSO_ADMIN_EMAIL` when deploying. After the first boot, sign in at `https://{your-domain}` with that address and the generated `DOCUMENSO_ADMIN_PASSWORD` from the Documenso service variables, then change the password in your profile. The account is verified and has admin rights.

**E-mail:** set `NEXT_PRIVATE_RESEND_API_KEY` and `NEXT_PRIVATE_SMTP_FROM_ADDRESS` (an address on a domain verified in Resend) and redeploy; the template switches to Resend automatically. Resend is an HTTP API and works on every Railway plan; SMTP works only on Railway Pro. Without e-mail you can still send by copying each recipient's signing link.

**Certificate:** the self-signed certificate is created once and kept on the volume, protected by `NEXT_PRIVATE_SIGNING_PASSPHRASE`. Do not change the passphrase afterwards. To use a CA-issued certificate, provide it as a base64 `.p12` in `NEXT_PRIVATE_SIGNING_LOCAL_FILE_CONTENTS` with its passphrase.

**Scaling:** scale the Documenso service vertically; Redis-backed jobs keep work durable across restarts. Gotenberg can be given more memory for large Word files.

**Versions:** change `DOCUMENSO_VERSION` in `services/documenso/Dockerfile` and redeploy; migrations run in the pre-deploy step, and a failed migration leaves the running version untouched.

### Why Deploy Documenso on Railway?

Railway runs the app, database, queue, converter and storage as one project on a private network, with managed volumes and usage-based billing. You get a complete, production-shaped e-signature service, including a working signing certificate, without running servers or hand-building PKCS#12 files.
