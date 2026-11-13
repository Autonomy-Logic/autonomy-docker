FROM node:22-bookworm-slim@sha256:e9f565d32859f0cbfb52125eafe8be39390f24dac302dc3cdf566e8ba3ab21ee AS node-upstream

FROM parent

COPY --from=node-upstream /usr/local/bin/node /usr/local/bin/node

RUN --mount=type=bind,source=git-smoke.sh,target=/usr/local/sbin/git-smoke.sh \
    apt-get update && \
    apt-get install -y --no-install-recommends systemd-standalone-sysusers stunnel4 openssl git wget libatomic1 && \
    ln -sf /usr/bin/stunnel4 /usr/bin/stunnel && \
    rm -f /etc/stunnel/stunnel.conf && \
    perl_packages="$(dpkg-query -Wf '${db:Status-Abbrev}${Package}\n' perl 'libperl5*' 'perl-modules-5*' liberror-perl git-man | sed -n 's/^ii //p')" && \
    echo "$perl_packages" | grep -q '^libperl5' && \
    dpkg --purge --force-depends $perl_packages && \
    rm -f /usr/lib/git-core/git-add--interactive /usr/lib/git-core/git-daemon /usr/lib/git-core/git-imap-send \
      /usr/lib/git-core/git-http-backend /usr/lib/git-core/git-http-push /usr/lib/git-core/git-http-fetch \
      /usr/lib/git-core/git-shell /usr/lib/git-core/scalar /usr/bin/git-shell /usr/bin/scalar && \
    rm -rf /var/lib/apt/lists/* /var/log/* /var/cache/ldconfig/aux-cache && \
    /usr/local/sbin/git-smoke.sh && \
    stunnel -version && \
    node --version
