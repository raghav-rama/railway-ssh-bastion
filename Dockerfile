FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        caddy \
        curl \
        openssh-server \
        tini \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/run/sshd /etc/caddy /run

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY docker/sshd_config /etc/ssh/sshd_config
COPY docker/Caddyfile.template /etc/caddy/Caddyfile.template

RUN chmod 0755 /usr/local/bin/entrypoint.sh

EXPOSE 2222 8080

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
