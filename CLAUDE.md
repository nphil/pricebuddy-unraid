# pricebuddy-unraid: notes for agents

Packaging only; PriceBuddy itself (jez500/pricebuddy) is never modified. Read README.md for
the design. Traps that already cost a debugging round:

- **`STOPSIGNAL SIGTERM` is load-bearing.** The php:apache base image stops with SIGWINCH
  (Apache's graceful stop), which supervisord ignores, so every `docker stop` waited out
  its timeout and then killed MariaDB mid-flight.
- **Supervisord logs only to stdout** (`logfile = /dev/null`, nodaemon echoes). Pointing
  `logfile` at `/dev/fd/1` prints every line twice.
- **MariaDB, not MySQL.** Upstream uses MySQL 8; SQLite is out because the code uses
  `ISNULL()` and JSON columns. Bookworm's MariaDB 10.11 runs the full migration set and
  the scrape path; revisit only if a migration ever fails on it.
- **The start script is patched by `sed` with a guard** (`grep -qx` on its last line). If
  upstream rewrites `docker/php/start-app.sh`, the build fails on purpose; re-read the
  script and adjust the two substitutions.
- The seleniumbase version comes from the scraper image (`pip show` in the first stage), so
  the scraper code and its library stay the pair upstream tested.
- Test an image on a real host before pushing: a push to `main` touching the image
  publishes a release.

Deployed on Nitin's beastnas (Unraid) as container `PriceBuddy`, documented in the
homelabber repo's seed doc `pricebuddy`.
