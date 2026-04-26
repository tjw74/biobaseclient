# Biobase monitoring — Grafana OSS with repo-baked provisioning.
# Latest OSS image; docker compose build --pull picks up new releases.
FROM grafana/grafana:latest

COPY --chown=472:0 provisioning/ /etc/grafana/provisioning/
