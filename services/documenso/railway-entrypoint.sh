#!/bin/sh
# Entrypoint for Documenso on Railway (runs as root, then drops to `nodejs`).
#  1. Picks the e-mail transport from the keys that are set (unless one is chosen explicitly).
#  2. Creates a self-signed signing certificate on the volume at first boot.
#  3. Checks that the stored certificate opens with NEXT_PRIVATE_SIGNING_PASSPHRASE.
#  4. Starts the optional first-admin bootstrap in the background.
#  5. Execs the official start script (migrations no-op after pre-deploy, then the server).
set -eu

log() { printf '[railway-entrypoint] %s\n' "$*"; }

# Any command other than the default start script (for example the pre-deploy migration, or a
# shell opened for debugging) runs unprivileged without the boot-time side effects below.
if [ "$*" != "sh start.sh" ]; then
    if [ "$(id -u)" = "0" ]; then
        exec su-exec nodejs "$@"
    fi
    exec "$@"
fi

# 1. E-mail transport. Empty = auto: Resend key -> resend, MailChannels key -> mailchannels,
#    otherwise SMTP (Railway allows outbound SMTP on Pro plans only).
if [ -z "${NEXT_PRIVATE_SMTP_TRANSPORT:-}" ]; then
    if [ -n "${NEXT_PRIVATE_RESEND_API_KEY:-}" ]; then
        NEXT_PRIVATE_SMTP_TRANSPORT=resend
    elif [ -n "${NEXT_PRIVATE_MAILCHANNELS_API_KEY:-}" ]; then
        NEXT_PRIVATE_SMTP_TRANSPORT=mailchannels
    else
        NEXT_PRIVATE_SMTP_TRANSPORT=smtp-auth
    fi
    export NEXT_PRIVATE_SMTP_TRANSPORT
fi
log "e-mail transport: ${NEXT_PRIVATE_SMTP_TRANSPORT}"
if [ "${NEXT_PRIVATE_SMTP_TRANSPORT}" = "smtp-auth" ] && [ -z "${NEXT_PRIVATE_SMTP_HOST:-}" ]; then
    log "no e-mail provider configured: signing requests and invitations will not be e-mailed (share signing links manually or set NEXT_PRIVATE_RESEND_API_KEY)"
fi

CERT_PATH="${NEXT_PRIVATE_SIGNING_LOCAL_FILE_PATH:-/opt/documenso/cert.p12}"
CERT_DIR="$(dirname "$CERT_PATH")"
PASSPHRASE_SET=false
[ -n "${NEXT_PRIVATE_SIGNING_PASSPHRASE:-}" ] && PASSPHRASE_SET=true

clean_subject_part() {
    # Keep the X.509 subject parseable: drop '/', '=', '+', quotes, backslashes and control
    # characters (BusyBox tr has no character classes, so use an octal range).
    printf '%s' "$1" | tr -d '/=+"\\' | tr -d '\001-\037\177' | cut -c1-64
}

generate_certificate() {
    cn="$(clean_subject_part "${SIGNING_CERT_COMMON_NAME:-${RAILWAY_PUBLIC_DOMAIN:-Documenso}}")"
    org="$(clean_subject_part "${SIGNING_CERT_ORGANIZATION:-Documenso Self-Hosted}")"
    days="${SIGNING_CERT_DAYS:-3650}"
    case "$days" in ''|*[!0-9]*) days=3650 ;; esac
    [ -n "$cn" ] || cn="Documenso"
    [ -n "$org" ] || org="Documenso Self-Hosted"

    work="$(mktemp -d)"
    log "creating a self-signed signing certificate (CN=${cn}, O=${org}, ${days} days, RSA 3072)"
    openssl req -x509 -newkey rsa:3072 -sha256 -days "$days" -nodes \
        -keyout "$work/key.pem" -out "$work/cert.pem" \
        -subj "/CN=${cn}/O=${org}" \
        -addext "basicConstraints=critical,CA:FALSE" \
        -addext "keyUsage=critical,digitalSignature,nonRepudiation" >/dev/null 2>&1
    openssl pkcs12 -export -out "$work/cert.p12" -inkey "$work/key.pem" -in "$work/cert.pem" \
        -name "Documenso signing certificate" -passout env:NEXT_PRIVATE_SIGNING_PASSPHRASE
    install -m 0400 -o nodejs "$work/cert.p12" "$CERT_PATH"
    rm -rf "$work"
    log "certificate stored at ${CERT_PATH} (keep the volume and the passphrase: both are needed to sign)"
}

if [ "$(id -u)" = "0" ]; then
    mkdir -p "$CERT_DIR"
    rmdir "$CERT_DIR/lost+found" 2>/dev/null || true

    if [ "${NEXT_PRIVATE_SIGNING_TRANSPORT:-local}" != "local" ]; then
        log "signing transport is ${NEXT_PRIVATE_SIGNING_TRANSPORT}: no local certificate needed"
    elif [ -n "${NEXT_PRIVATE_SIGNING_LOCAL_FILE_CONTENTS:-}" ]; then
        log "using the certificate supplied in NEXT_PRIVATE_SIGNING_LOCAL_FILE_CONTENTS"
    else
        # 2. First boot on this volume: create the certificate.
        if [ ! -s "$CERT_PATH" ]; then
            if [ "$PASSPHRASE_SET" = "true" ] && [ "${SIGNING_CERT_AUTOGENERATE:-true}" = "true" ]; then
                generate_certificate
            else
                log "WARNING: no certificate at ${CERT_PATH} and auto-generation is off or NEXT_PRIVATE_SIGNING_PASSPHRASE is empty; documents cannot be sealed"
            fi
        fi
        # 3. Make sure the certificate is readable by the app and opens with the passphrase.
        if [ -s "$CERT_PATH" ]; then
            chown nodejs "$CERT_PATH" 2>/dev/null || true
            chmod 0400 "$CERT_PATH" 2>/dev/null || true
            if openssl pkcs12 -in "$CERT_PATH" -noout -passin env:NEXT_PRIVATE_SIGNING_PASSPHRASE >/dev/null 2>&1; then
                log "signing certificate OK"
            else
                log "ERROR: ${CERT_PATH} does not open with NEXT_PRIVATE_SIGNING_PASSPHRASE. Restore the previous passphrase, or delete the file to create a new certificate (documents signed earlier stay valid)."
            fi
        fi
    fi
    chown nodejs "$CERT_DIR" 2>/dev/null || true

    # 4. First-admin bootstrap (no-op without DOCUMENSO_ADMIN_EMAIL).
    if [ -n "${DOCUMENSO_ADMIN_EMAIL:-}" ]; then
        su-exec nodejs node /app/apps/remix/railway/bootstrap-admin.cjs &
    fi

    # 5. Hand over to the official start script as the unprivileged user.
    exec su-exec nodejs "$@"
fi

# Already unprivileged (custom RAILWAY_RUN_UID): skip volume preparation.
log "running as uid $(id -u): skipping certificate preparation"
if [ -n "${DOCUMENSO_ADMIN_EMAIL:-}" ]; then
    node /app/apps/remix/railway/bootstrap-admin.cjs &
fi
exec "$@"
