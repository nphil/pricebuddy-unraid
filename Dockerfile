# PriceBuddy (jez500/pricebuddy) as one container: the upstream app image, plus the
# database and the headless-browser scraper that upstream ships as two more containers.
# Nothing of PriceBuddy itself is changed; see README.md for the design.
ARG PRICEBUDDY_VERSION=latest
ARG SCRAPER_VERSION=latest

FROM jez500/seleniumbase-scrapper:${SCRAPER_VERSION} AS scraper
# Remember which SeleniumBase the scraper was built and tested against.
RUN python3 -m pip show seleniumbase | awk '/^Version:/{print $2}' >/seleniumbase-version

FROM jez500/pricebuddy:${PRICEBUDDY_VERSION}

# MariaDB replaces upstream's MySQL container. Chrome, Xvfb and Python come from the
# same list the scraper image installs.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        mariadb-server python3 python3-venv wget ca-certificates xvfb \
        fonts-liberation fonts-open-sans fonts-roboto fonts-lato \
    && wget -q -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
    && apt-get install -y --no-install-recommends /tmp/chrome.deb \
    && rm /tmp/chrome.deb \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# The scraper's own API code, byte for byte, at the path it expects.
COPY --from=scraper /SeleniumBase /SeleniumBase
COPY --from=scraper /seleniumbase-version /SeleniumBase/.seleniumbase-version
RUN python3 -m venv /opt/scraper \
    && /opt/scraper/bin/pip install --no-cache-dir --upgrade pip setuptools wheel \
    && /opt/scraper/bin/pip install --no-cache-dir \
        "seleniumbase==$(cat /SeleniumBase/.seleniumbase-version)" flask beautifulsoup4 \
    && /opt/scraper/bin/seleniumbase get chromedriver --path \
    && mkdir -p /SeleniumBase/api/cache /SeleniumBase/api/screenshots /SeleniumBase/api/user_scripts

# Upstream's start script ends by starting supervisord. Here supervisord is already
# running (it also owns the database and the scraper), so the script's last line becomes
# "start the app's programs" and its env dump, which would print the DB password, goes.
RUN grep -qx 'supervisord -c /etc/supervisor/conf.d/supervisord.conf' /start-app.sh \
    && sed -i \
        -e 's#^supervisord -c /etc/supervisor/conf.d/supervisord.conf$#exec supervisorctl -c /etc/pricebuddy/supervisord.conf start app:*#' \
        -e '/^printenv$/d' \
        /start-app.sh

RUN echo "ServerName localhost" >/etc/apache2/conf-enabled/servername.conf

COPY rootfs/ /
RUN chmod +x /usr/local/bin/*

ENV SCRAPER_BASE_URL=http://127.0.0.1:3000 \
    DB_CONNECTION=mysql DB_HOST=127.0.0.1 DB_PORT=3306 \
    DB_DATABASE=pricebuddy DB_USERNAME=pricebuddy \
    TZ=UTC

VOLUME /config
EXPOSE 80
# The php:apache base stops with SIGWINCH (graceful Apache); supervisord needs TERM
# to stop everything in order, the database last.
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=30s --timeout=10s --start-period=180s --retries=5 \
    CMD curl -fsS -o /dev/null http://127.0.0.1/ || exit 1
ENTRYPOINT ["/usr/local/bin/pricebuddy-entrypoint"]
