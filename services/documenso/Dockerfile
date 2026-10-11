# Documenso for Railway: the official image plus
#  - a root entrypoint that creates a self-signed signing certificate (.p12) on the
#    volume at first boot, fixes volume ownership and drops to the image's `nodejs` user,
#  - a pre-deploy migration script that waits for Postgres,
#  - an optional first-admin bootstrap (DOCUMENSO_ADMIN_EMAIL).
#
# Upgrade Documenso by changing DOCUMENSO_VERSION and redeploying.
ARG DOCUMENSO_VERSION=v2.20.0
FROM documenso/documenso:${DOCUMENSO_VERSION}

USER root

# su-exec: drop from root to `nodejs` after preparing the volume (busybox setpriv cannot change uid).
RUN set -eux; \
    apk add --no-cache su-exec; \
    mkdir -p /opt/documenso /app/apps/remix/railway; \
    chown nodejs /opt/documenso; \
    su-exec nodejs true

COPY railway-entrypoint.sh documenso-migrate.sh /usr/local/bin/
COPY bootstrap-admin.cjs /app/apps/remix/railway/bootstrap-admin.cjs

RUN set -eux; \
    chmod 0755 /usr/local/bin/railway-entrypoint.sh /usr/local/bin/documenso-migrate.sh; \
    chmod 0644 /app/apps/remix/railway/bootstrap-admin.cjs; \
    sh -n /usr/local/bin/railway-entrypoint.sh; \
    sh -n /usr/local/bin/documenso-migrate.sh; \
    node --check /app/apps/remix/railway/bootstrap-admin.cjs

ENV NEXT_PRIVATE_SIGNING_LOCAL_FILE_PATH=/opt/documenso/cert.p12

WORKDIR /app/apps/remix
EXPOSE 3000
ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
CMD ["sh", "start.sh"]
