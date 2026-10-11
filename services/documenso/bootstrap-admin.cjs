// First-admin bootstrap for Documenso on Railway.
//
// When DOCUMENSO_ADMIN_EMAIL is set, this script waits for the server, creates that account
// through Documenso's own sign-up endpoint (so organisations, teams and password hashing are
// handled by the app), then marks the e-mail as verified and grants the ADMIN role.
// This lets the owner sign in without an e-mail provider. It never touches an existing
// account unless that account is the only user of the instance (a retry of an earlier boot).
'use strict';

const { PrismaClient } = require('@prisma/client');

const PREFIX = '[bootstrap-admin]';
const log = (msg) => console.log(`${PREFIX} ${msg}`);
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const SPECIAL_RE = /[`~<>?,./!@#$%^&*()\-_"'+=|{}[\];:\\]/;

const passwordIsAccepted = (password) => {
  if (password.length < 8 || password.length > 72) return false;
  if (password.length > 25) return true;
  return /[A-Z]/.test(password) && /[a-z]/.test(password) && /\d/.test(password) && SPECIAL_RE.test(password);
};

const waitForServer = async (baseUrl) => {
  const deadline = Date.now() + 20 * 60 * 1000;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(`${baseUrl}/api/health`);
      if (response.ok) return true;
    } catch {
      // Server not listening yet.
    }
    await sleep(5000);
  }
  return false;
};

const signUp = async (baseUrl, { name, email, password }) => {
  // Documenso's CSRF guard only accepts mutations whose Origin is NEXT_PUBLIC_WEBAPP_URL.
  const origin = new URL(process.env.NEXT_PUBLIC_WEBAPP_URL || baseUrl).origin;
  const response = await fetch(`${baseUrl}/api/auth/email-password/signup`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Origin: origin },
    body: JSON.stringify({ name, email, password }),
  });
  if (!response.ok) {
    const body = (await response.text()).slice(0, 300);
    throw new Error(`sign-up returned HTTP ${response.status}: ${body}`);
  }
};

const promote = (prisma, id) =>
  prisma.user.update({
    where: { id },
    data: { emailVerified: new Date(), roles: { set: ['ADMIN', 'USER'] } },
  });

const main = async () => {
  const email = (process.env.DOCUMENSO_ADMIN_EMAIL || '').trim().toLowerCase();
  const password = process.env.DOCUMENSO_ADMIN_PASSWORD || '';
  const name = (process.env.DOCUMENSO_ADMIN_NAME || 'Administrator').trim() || 'Administrator';
  const port = process.env.PORT || '3000';
  const baseUrl = `http://127.0.0.1:${port}`;

  if (!email) return;
  if (!EMAIL_RE.test(email)) {
    log(`DOCUMENSO_ADMIN_EMAIL "${email}" is not a valid e-mail address; skipping`);
    return;
  }
  if (!passwordIsAccepted(password)) {
    log('DOCUMENSO_ADMIN_PASSWORD must be 26-72 characters, or 8-25 with upper, lower, digit and symbol; skipping');
    return;
  }

  if (!(await waitForServer(baseUrl))) {
    log('server did not become healthy within 20 minutes; skipping');
    return;
  }

  const prisma = new PrismaClient();
  try {
    let user = await prisma.user.findUnique({ where: { email } });

    if (user && user.roles.includes('ADMIN')) {
      log(`admin account ${email} already exists; nothing to do`);
      return;
    }

    if (user) {
      // Documenso's migrations add system accounts on @localhost; they are not real users.
      const userCount = await prisma.user.count({
        where: { NOT: { email: { endsWith: '@localhost' } } },
      });
      if (userCount !== 1) {
        log(`an account for ${email} exists but is not an admin and other users exist; not changing it`);
        return;
      }
      log(`completing set-up of ${email} (only account on this instance)`);
    } else {
      log(`creating the first admin account ${email}`);
      await signUp(baseUrl, { name, email, password });
      user = await prisma.user.findUnique({ where: { email } });
      if (!user) throw new Error('account not found after sign-up');
    }

    await promote(prisma, user.id);
    log(`${email} is verified and has the ADMIN role. Sign in with the password stored in DOCUMENSO_ADMIN_PASSWORD.`);
  } finally {
    await prisma.$disconnect();
  }
};

main().catch((error) => {
  log(`failed: ${error && error.message ? error.message : error}`);
  process.exitCode = 1;
});
