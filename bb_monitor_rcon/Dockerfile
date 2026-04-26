# Biobase RCON -> Prometheus (same protocol as bb_cs2_server rcon.sh / mcrcon).
FROM python:3.12-slim

ARG MCRCON_VERSION=0.7.1
ARG MCRCON_URL=https://github.com/Tiiffi/mcrcon/releases/download/v${MCRCON_VERSION}/mcrcon-${MCRCON_VERSION}-linux-x86-64.tar.gz

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl \
    && curl -fsSL -o /tmp/mcrcon.tgz "${MCRCON_URL}" \
    && tar -xzf /tmp/mcrcon.tgz -C /tmp \
    && mv /tmp/mcrcon-*/mcrcon /usr/local/bin/mcrcon \
    && chmod +x /usr/local/bin/mcrcon \
    && rm -rf /tmp/mcrcon-* \
    && rm /tmp/mcrcon.tgz && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY collector.py .
RUN useradd -r -s /usr/sbin/nologin bb
USER bb
EXPOSE 9105
# RCON_PASSWORD set at deploy time (e.g. docker-compose); never a real default in the image.
ENV RCON_HOST=bb_cs2_server RCON_PORT=27015 RCON_POLL_INTERVAL=10 \
    METRICS_PORT=9105 MCRCON_BIN=/usr/local/bin/mcrcon
CMD ["python", "/app/collector.py"]
