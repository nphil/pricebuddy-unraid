<p align="center"><img src="assets/icon.png" width="112" alt=""></p>

<h1 align="center">PriceBuddy for Unraid</h1>

<p align="center"><a href="https://github.com/jez500/pricebuddy">PriceBuddy</a>, the self-hosted price tracker, as <b>one container</b>.</p>

PriceBuddy normally runs as three containers: the app, a MySQL database and a headless
Chrome scraper. This image puts all three in one, so your server sees one app, one port
and one update button. PriceBuddy itself runs unmodified.

- **One container.** The app, its database and the Chrome scraper, under one supervisor
  that starts them in order and stops the database last.
- **Normal updates.** Each image is built on a PriceBuddy release and tagged with its
  version. A new release becomes a new image within about six hours, so Unraid shows
  *update available*, and the release notes list what changed upstream.
- **Portable.** Everything lives in one folder. Copy it to another machine, run the same
  image, and it comes up as it was.

## Install

**Unraid:** Docker, Add Container, Template URL
`https://raw.githubusercontent.com/nphil/pricebuddy-unraid/main/unraid/pricebuddy.xml`.

**Anywhere else:**

```bash
docker run -d --name pricebuddy --stop-timeout 90 -p 8095:80 \
  -v /fast/pricebuddy:/config \
  -e APP_URL=https://prices.example.com \
  -e ADMIN_EMAIL=you@example.com \
  -e TZ=America/New_York \
  ghcr.io/nphil/pricebuddy-unraid:latest
```

Log in with the admin email. The password is the one you set in `ADMIN_PASSWORD`, or
else the generated one in `secrets.env` in the app data folder. Change it in the app
afterwards; the variable only matters on first start.

| Variable | Default | What it does |
| --- | --- | --- |
| `APP_URL` | *(empty)* | The address you open PriceBuddy at. Set it when a reverse proxy is in front. |
| `ADMIN_EMAIL` | `admin@example.com` | The first user, created on first start. |
| `ADMIN_PASSWORD` | *(generated)* | That user's password, first start only. |
| `DEFAULT_STORES_COUNTRY` | `all` (template: `usa`) | Built-in stores to create on first start: `usa`, `australia` or `all`. |
| `AFFILIATE_ENABLED` | upstream's | Upstream's affiliate tagging of some store links. |
| `AI_COMPAT_URL` | *(empty)* | A llama.cpp or llama-swap server for PriceBuddy's AI, base URL without `/v1`. See below. |
| `TZ` | `UTC` | Time zone for the price check schedule. |

Any other PriceBuddy or Laravel variable works as documented upstream.

## What is in `/config`

| Path | Holds |
| --- | --- |
| `mysql/` | The MariaDB database: products, prices, stores, users, settings |
| `storage/` | Upstream's `/app/storage`: logs and uploads |
| `app.env` | Upstream's `.env`, including `APP_KEY`, which encrypts stored API keys |
| `secrets.env` | Generated database and first admin passwords |

Keep `app.env` with the database. Without its `APP_KEY`, saved API keys (AI providers,
notification tokens) can no longer be decrypted.

## How it fits together

| Process | What it is |
| --- | --- |
| `mariadb` | Stands in for upstream's MySQL container, on `127.0.0.1:3306` only |
| `scraper` | The API of [jez500/seleniumbase-scrapper](https://github.com/jez500/seleniumbase-scrapper), copied from its image, with the same SeleniumBase version and Google Chrome, on `127.0.0.1:3000` only |
| `init` | Upstream's own start script: waits for the database, migrates, warms caches, then starts the three below |
| `ai-compat` | The llama.cpp proxy above, on `127.0.0.1:9380` only; idle unless `AI_COMPAT_URL` is set |
| `apache2`, `cron`, `queue-worker` | Upstream's own programs, unchanged |

Two lines of upstream's start script are changed at build time, and the build fails if
they ever stop matching: the final `supervisord` becomes "start the app's programs"
(supervisord is already running), and the `printenv` debug line goes, because it would
print the database password into the log.

The scraper's Chrome and PriceBuddy are both fixed at build time. A new PriceBuddy release
rebuilds everything, which also brings a current Chrome. For a Chrome update between
releases, run the workflow by hand.

## AI on llama.cpp or llama-swap

PriceBuddy's AI (price recovery and store-rule repair) asks for replies in a fixed JSON
shape through OpenAI's `/v1/responses`. llama.cpp answers that endpoint but ignores the
requested shape, so every AI call fails. Set `AI_COMPAT_URL` to the server (for example
`http://192.168.1.10:9292`) and, in PriceBuddy's Settings under Integrations, add an
**OpenAI** provider with base URL **`http://127.0.0.1:9380/v1`**, any API key, and your
model's name. A small proxy inside the container passes the requested shape on in the form
llama.cpp enforces; everything else goes through unchanged. OpenAI, Anthropic and Gemini
need none of this.

## Operating it

```bash
docker logs PriceBuddy
docker exec PriceBuddy supervisorctl -c /etc/pricebuddy/supervisord.conf status
docker exec PriceBuddy cat /app/storage/logs/laravel.log
docker exec PriceBuddy mariadb pricebuddy       # database shell, as root over the socket
```

amd64 only, because the scraper uses Google Chrome, which has no arm64 build.
