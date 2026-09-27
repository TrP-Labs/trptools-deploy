# TrPTools deploy

Run TrPTools on your own server with Docker Compose: Postgres, Valkey, Garage, the API, and the site. Images support AMD64 and ARM64; the Discord bot is optional.

## Docker

1. Install Docker with Compose v2, Git, and OpenSSL.
2. Run `git clone https://github.com/TrP-Labs/trptools-deploy.git && cd trptools-deploy`.
3. Run `./scripts/setup.sh` to create `.env` and generate secrets.
4. Run `docker compose up -d` when you are ready to start.
5. Open `http://localhost:3000` (or the site URL you entered).

## Public access

1. Point your site, API, and image domains at the server and enable HTTPS with your reverse proxy.
2. Proxy the site to port `3000`, the API to `3001`, and images to `9000`; keep internal services private.
3. Set `FRONTEND_URL`, `BASE_URL`, and `S3_PUBLIC_URL` to those HTTPS origins in `.env`.
4. Set `COOKIE_DOMAIN` to their shared parent domain, such as `.example.com`, then run `docker compose up -d`.

Garage creates the media bucket automatically; the image proxy serves public reads only. This single-server setup has no storage redundancy, so back up Postgres and Garage.

## Roblox sign-in

1. Create an OAuth app in the [Roblox Creator Dashboard](https://create.roblox.com/dashboard/credentials).
2. Enable `openid`, `profile`, and `group:read`, and register `<BASE_URL>/auth/callback`.
3. Set `ROBLOX_CLIENT_ID` and `ROBLOX_CLIENT_SECRET` in `.env`, then run `docker compose up -d`.

Groups can add an Open Cloud key in their dashboard settings. The key must belong to a Roblox user account.

## Discord (optional)

1. Create an app at the [Discord Developer Portal](https://discord.com/developers/applications).
2. Register `<BASE_URL>/bot/callback` and `<BASE_URL>/auth/discord/callback` as OAuth redirects.
3. Set `DISCORD_APP_ID`, `DISCORD_CLIENT_SECRET`, and `DISCORD_BOT_TOKEN` in `.env`.
4. Run `docker compose --profile bot up -d`, then connect your server from the group dashboard.

## Cloudflare Workers

Use the [backend](https://github.com/TrP-Labs/trptools-backend#cloudflare-workers), [frontend](https://github.com/TrP-Labs/trptools-frontend#cloudflare-workers), and [bot](https://github.com/TrP-Labs/trptools-bot#cloudflare-workers) setup instructions. Workers use Neon, Upstash REST, and R2 or another reachable S3 service; this Compose stack is for Docker.

## Update

1. Run `git pull --ff-only`.
2. Set `TAG` in `.env` to a release such as `2.12.0` (without `v`), or keep `latest`.
3. Run `docker compose pull && docker compose up -d` (add `--profile bot` to both commands if needed).
4. Check `docker compose ps` and `docker compose logs --tail=50 backend frontend`.

The API applies migrations on startup. Footer documents refresh from `POLICIES_REPOSITORY` (default `TrP-Labs/Policies`); set it to your fork to use your own documents.

## Existing MinIO installs

Back up the old bucket and copy its objects to Garage before switching; this update does not migrate media or delete the old volume. Run `./scripts/setup.sh --garage` to replace only storage settings, preserving database and encryption secrets, and use an image URL without the old bucket suffix.

## Stop and back up

1. Run `docker compose exec -T postgres pg_dump -U trptools trptools > backup.sql` to back up the database.
2. Stop the stack with `docker compose --profile bot down` and back up its `garage-data` volume before an upgrade.
3. Run `docker compose up -d` (or `docker compose --profile bot up -d`) to restart; keep `.env` with your backups.

Avoid `down -v`: it deletes the data volumes. Garage stores metadata and objects together in `garage-data`.
