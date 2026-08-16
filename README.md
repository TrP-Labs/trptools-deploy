# TrP Tools — deploy

Run your own instance of [TrP Tools](https://github.com/TrP-Labs) — group
management, shift scheduling and multi-user dispatch for the Roblox transit
game TrP — on your own server with Docker.

This repo does not contain any application source. It pulls prebuilt images
published by [`trptools-backend`](https://github.com/TrP-Labs/trptools-backend),
[`trptools-frontend`](https://github.com/TrP-Labs/trptools-frontend) and the
optional [`trptools-bot`](https://github.com/TrP-Labs/trptools-bot) from GitHub
Container Registry every time you `docker compose pull`.

## Requirements

- A server with Docker and the Compose v2 plugin (`docker compose version`
  should work).
- `openssl` and `curl` (present on essentially every Linux distro and macOS).
- A [Roblox app](https://create.roblox.com/dashboard/credentials) for OAuth —
  can be added after your first deploy.

## Quick start

```bash
git clone https://github.com/TrP-Labs/trptools-deploy.git
cd trptools-deploy
./scripts/setup.sh
docker compose up -d
```

`setup.sh` asks a few questions (or accept the defaults for a local trial),
generates the `ENCRYPTION_KEY`, database password and object-storage keys,
and writes `.env`. It will not overwrite an existing `.env` without asking.

Once containers are up, the site is at `FRONTEND_URL` (default
`http://localhost:3000`) and the API at `BASE_URL` (default
`http://localhost:3001`). The API applies its own database migrations on
start, so a fresh deploy comes up ready.

## No bundled TLS

This compose file exposes plain HTTP on the ports above — it doesn't run a
reverse proxy or manage certificates. For anything but a local trial, put one
in front: [Caddy](https://caddyserver.com) (`reverse_proxy` + automatic
HTTPS is a few lines), nginx with certbot, or a tunnel like Cloudflare
Tunnel. Point it at `127.0.0.1:3000` for the site and `127.0.0.1:3001` for
the API, and set `BASE_URL`/`FRONTEND_URL` in `.env` to the public
`https://` addresses before running `setup.sh` (or edit them into `.env`
afterwards and restart).

## Setting up Roblox

TrP Tools authenticates exclusively with Roblox OAuth.

1. Create an app at [Creator Dashboard credentials](https://create.roblox.com/dashboard/credentials).
2. Enable the `openid`, `profile` and **`group:read`** permissions.
3. Set the redirect URI to `<BASE_URL>/auth/callback`.
4. Put the client ID and secret in `.env` as `ROBLOX_CLIENT_ID` /
   `ROBLOX_CLIENT_SECRET`, then `docker compose up -d` again.

Each group additionally supplies its own Open Cloud API key in group
settings once the site is running — see the backend's README for why.

## Setting up the Discord bot

Optional. Without it the site works exactly as it does otherwise — groups just
have no Discord server to connect. With it, a group can announce shifts, run
staff sign-up sheets that stay in step with the website, and post a live picture
of the dispatch board.

1. Create an application at the
   [Discord developer portal](https://discord.com/developers/applications).
2. On **OAuth2**, add `<BASE_URL>/bot/callback` as a redirect URI. Without this
   the dashboard's "Add to Discord" button is refused — and there is no API to
   set it, so it has to be done by hand.
3. On **Bot**, create a token. No privileged intents are needed: the bot never
   reads message content, members or presence.
4. Put the application ID, client secret and bot token in `.env` as
   `DISCORD_APP_ID`, `DISCORD_CLIENT_SECRET` and `DISCORD_BOT_TOKEN`
   (`setup.sh` asks for all three).
5. Start it:

```bash
docker compose --profile bot up -d
```

The bot runs under a compose profile, so a plain `docker compose up -d` leaves
it out — including on later upgrades. Keep the `--profile bot` flag, or set
`COMPOSE_PROFILES=bot` in your environment once and forget about it.

Upgrading an existing instance rather than setting one up? `setup.sh` writes
`.env` from scratch and would replace your secrets, so add these by hand
instead — the last one is a secret you invent, shared between the API and the
bot:

```bash
DISCORD_APP_ID=
DISCORD_CLIENT_SECRET=
DISCORD_BOT_TOKEN=
BOT_SERVICE_TOKEN=$(openssl rand -hex 32)
```

Slash commands register themselves each time the container starts. Global
commands can take up to an hour to appear in a server the first time.

One group manager then connects a server from the dashboard's **Bot** page, and
configures everything else — channels, ping roles, which features are on, and
what the bot does on its own — from there. Nothing about the bot is configured
in `.env` beyond the credentials above.

## Terms and privacy pages

The frontend reads `TERMS.md`/`PRIVACY.md` from `./policies` at container
start (mounted read-only), not from its image. Two ways to populate it:

```bash
./scripts/pull-policies.sh                       # TrP-Labs/Policies, "prod" branch
./scripts/pull-policies.sh your-org/Policies main # your own fork/repo
```

or just drop `TERMS.md`/`PRIVACY.md` into `./policies` yourself. Either way,
`docker compose restart frontend` afterwards — the files are read once at
startup, not per request. An empty `./policies` means the site has no
terms/privacy pages and no footer links to them.

## Updating

```bash
docker compose pull
docker compose up -d
```

Add `--profile bot` to both commands if you run the Discord bot, or it is left
at its old image.

`TAG` in `.env` controls which image tag is deployed — `latest` (default)
tracks `main` in every source repo; pin it to a release like `v1.2.3` for a
more predictable upgrade cadence. Database migrations run automatically as
part of the backend container's startup.

### Upgrading to 2.1.0

**Shift sign-ups were rebuilt, and the upgrade does not carry the old ones
over.** Sign-up slots used to be defined on each shift; they now belong to a
Roblox rank and apply to every shift that rank works. There is no honest
automatic mapping between the two — a rank has one sheet, while slots were
per shift and per occurrence — so the 2.1.0 migration drops the old
`shift_slots` and `shift_signups` tables rather than guessing.

In practice: after upgrading, define a sheet per rank on the dashboard's
**Ranks** page. Anyone signed up for a *future* shift under the old model will
need to sign up again.

Take a backup first if those rows matter to you:

```bash
docker compose exec -T postgres pg_dump -U trptools trptools > trptools-backup.sql
```

## What's in `.env`

| Variable                              | What it's for                                                            |
| -------------------------------------- | -------------------------------------------------------------------------- |
| `BASE_URL` / `FRONTEND_URL`            | Public origins of the API and the site                                    |
| `ENCRYPTION_KEY`                       | Encrypts stored Roblox OAuth tokens and group Open Cloud keys             |
| `ROBLOX_CLIENT_ID` / `_SECRET`         | Roblox OAuth app credentials                                              |
| `SITE_ADMINS`                          | Comma-separated Roblox user IDs granted the site-wide admin rank          |
| `COOKIE_DOMAIN`                        | Parent domain the session cookie is scoped to — see below                 |
| `POSTGRES_PASSWORD`                    | Database password (generated; Postgres isn't exposed outside the network) |
| `S3_ACCESS_KEY` / `S3_SECRET_KEY`      | MinIO credentials (generated)                                             |
| `S3_PUBLIC_URL`                        | Where browsers fetch uploaded route/depot images from                     |
| `DISCORD_APP_ID` / `_CLIENT_SECRET` / `_BOT_TOKEN` | Discord application credentials, for the optional bot          |
| `BOT_SERVICE_TOKEN`                    | Shared secret the bot authenticates to the API with (generated)           |
| `TAG`                                  | Image tag to deploy                                                       |

All of these except `TAG` are filled in by `./scripts/setup.sh`. The Discord
ones may be left blank; everything else works without them.

### Sign-in works on the API but the site still shows you signed out

You're missing `COOKIE_DOMAIN`. When the site and API are on different
hostnames — say `trptools.com` and `apis.trptools.com` — the session cookie
defaults to *host-only* on the API's hostname. The browser dutifully sends it
back to the API, which is why signing in appears to succeed, but it never
sends it to the site, so server-side rendering sees an anonymous visitor on
every page load.

Set it to the shared parent, with the leading dot:

```bash
COOKIE_DOMAIN=.trptools.com
```

then `docker compose up -d` and sign in again — the old host-only cookie is
still in your browser and won't be replaced until you do.

`setup.sh` works this out from your two URLs and offers it as a default, so a
fresh install doesn't hit this. Leave it blank when the site and API share one
hostname.

## License

MIT — see [LICENSE](./LICENSE). The application source has its own MIT
licenses: [trptools-backend](https://github.com/TrP-Labs/trptools-backend),
[trptools-frontend](https://github.com/TrP-Labs/trptools-frontend),
[trptools-bot](https://github.com/TrP-Labs/trptools-bot).
