# Deploying stera-open on EC2

This guide covers deploying the Bun + Hono API (`apps/server`) on a single EC2 instance with nginx reverse proxy and PostgreSQL (managed, e.g. Neon/Supabase/RDS).

## Prerequisites

- Ubuntu EC2 instance with Bun installed (`~/.bun/bin/bun`)
- PostgreSQL database with:
  - **`DATABASE_URL`** — pooled connection (PgBouncer / transaction pooler, typically port **6543**)
  - **`DIRECT_URL`** — direct session connection for migrations (port **5432**)
- Cloudflare R2 bucket + API token (S3-compatible credentials)
- DNS for **`api.example.com`** pointing at the EC2 public IP (or load balancer)
- OAuth credentials (see [Credentials still required](#credentials-still-required))

## 1. Clone and install

```bash
git clone <repo-url> /home/ubuntu/stera-open
cd /home/ubuntu/stera-open
bun install
```

## 2. Configure environment

```bash
cp apps/server/.env.example apps/server/.env
# Edit apps/server/.env with production values
```

Important variables:

| Variable | Notes |
| --- | --- |
| `DATABASE_URL` | App runtime — **transaction pooler** on `aws-1-ap-south-1.pooler.supabase.com:6543` (`?pgbouncer=true`) |
| `DIRECT_URL` | Drizzle migrations — **session pooler** on the same host **`:5432`**. Do **not** use `db.<ref>.supabase.co`: that hostname is IPv6-only and this EC2 box has no IPv6 route (`Network is unreachable`). |
| `BETTER_AUTH_URL` | Public API origin, e.g. `https://api.example.com` |
| `TRUSTED_ORIGINS` | Comma-separated origins Better Auth accepts (include `https://appleid.apple.com`) |
| `CORS_ALLOWED_ORIGINS` | Real origin only (`https://api.example.com`) — never `*` with credentialed cookies |
| `NODE_ENV` | `production` even on the open-dev box — runtime mode, not deployment environment |
| `UPLOAD_URL_EXPIRY_SECONDS` | `86400` (matches live egoapp-backend; client refreshes at T-10 min) |

## 3. Run database migrations

```bash
cd /home/ubuntu/stera-open
bun run db:migrate
```

Uses `DIRECT_URL` from `apps/server/.env` via `packages/db/drizzle.config.ts`.

## 4. Build the server

```bash
bun run build -F server
```

Output: `apps/server/dist/index.mjs`

## 5. systemd service

```bash
sudo cp deploy/stera-server.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable stera-server
sudo systemctl start stera-server
sudo systemctl status stera-server
```

The service runs `bun run dist/index.mjs` on port **3010** (configurable via `PORT`).

## 6. nginx

```bash
sudo cp deploy/client-max-body-size.conf /etc/nginx/conf.d/
sudo cp deploy/nginx.conf /etc/nginx/conf.d/api.example.com.conf
sudo nginx -t
sudo systemctl reload nginx
```

### Cloudflare + HTTP-01 TLS caveat

If **`api.example.com` is proxied through Cloudflare** (orange cloud), Let's Encrypt HTTP-01 validation from `certbot --nginx` will fail unless:

- You temporarily set the DNS record to **DNS only** (grey cloud) during certificate issuance, or
- You use Cloudflare Origin certificates / Full (Strict) with a Cloudflare-managed cert instead of certbot HTTP-01, or
- You use DNS-01 validation

After TLS is working, re-enable Cloudflare proxy if desired. Ensure `X-Forwarded-Proto` reaches the app (nginx sets this in `deploy/nginx.conf`).

## 7. Smoke test

```bash
curl -s https://api.example.com/health
# => { "ok": true }

curl -s https://api.example.com/api/auth/ok
curl -s https://api.example.com/api/auth/get-session
```

## Credentials still required

These live in neither the old app nor egoapp-backend today — Supabase Auth held them. Move them into `apps/server/.env` before go-live:

- **`GOOGLE_CLIENT_SECRET`** — Supabase dashboard → Authentication → Providers → Google, or GCP Credentials for the web OAuth client
- **Apple Sign In** — `APPLE_CLIENT_ID` (Services ID), `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY` (`.p8` PEM from Apple Developer → Keys), `APPLE_APP_BUNDLE_IDENTIFIER` (`io.rootlens.app`)
- **`BETTER_AUTH_SECRET`** — `openssl rand -base64 32` at deploy time if not supplied

R2 + Google client IDs + Postgres URLs are already known for the open-dev box.

## Existing users

The new Supabase Postgres project is empty. This is a **clean break** — current dev/prod accounts do not carry over; everyone re-signs-in. A later migration could re-link `account` rows by provider subject if needed.

## Updating

```bash
cd /home/ubuntu/stera-open
git pull
bun install
bun run db:migrate
bun run build -F server
sudo systemctl restart stera-server
```

## Mobile app

The Flutter app at `apps/mobile` talks to `https://api.example.com/api/v1/*` and Better Auth at `/api/auth/*`. Sync Google client IDs before building:

```bash
bun run pub-get:mobile
```
