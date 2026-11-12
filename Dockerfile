# Operator helper image for the EmpowerU community access-monitoring toolkit.
#
# By default this image runs read-only collection INSIDE the container
# filesystem. It does not monitor the host unless you bind-mount host
# paths after review. It never runs apply mutations.
#
# Build:  docker build -t eu-ec-detect-community .
# Run:    docker compose run --rm eu-collect
#
# Debian bookworm's sed is GNU sed, which the redaction helpers require.

FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        coreutils \
        gawk \
        iproute2 \
        procps \
        python3 \
        sed \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 10001 euoperator \
    && useradd --system --uid 10001 --gid 10001 --create-home --shell /bin/bash euoperator

WORKDIR /opt/eu-ec-detect

COPY vendor/eu-ec-detect-community/ /opt/eu-ec-detect/

RUN chmod 0755 /opt/eu-ec-detect/scripts/*.sh \
    && mkdir -p /opt/eu-ec-detect/reports \
    && chown -R euoperator:euoperator /opt/eu-ec-detect \
    && chmod 0700 /opt/eu-ec-detect/reports

USER euoperator

# Read-only default. Do not set CONFIRM=yes in this image.
ENTRYPOINT ["/opt/eu-ec-detect/scripts/easy-run.sh"]
