# Biobase CS2 dedicated server: joedwards32/cs2 + Metamod:Source 2 (CS2) + CS2KZ (KZGlobalTeam).
# Pinned versions — bump when upgrading; verify SHA256 on GitHub release assets.

FROM joedwards32/cs2:latest

USER root

ARG METAMOD_TAG=2.0.0.1396
ARG METAMOD_FILE=mmsource-2.0.0-git1396-linux.tar.gz
ARG METAMOD_SHA256=22a6b00932b9d14f014ad09754e28d6ad54a9d81649584c772e7cd2213b0c3ef

ARG CS2KZ_TAG=v0.0.125
ARG CS2KZ_FILE=cs2kz-linux-master.tar.gz
ARG CS2KZ_SHA256=e221676f60bcd907dbb8117fefad5768f3843cddd8b384c4e8e101eacde46ffd

# Optional for upstream CS2KZ but required for local SQLite gameplay DB (times, jumpstats, players).
# https://github.com/zer0k-z/sql_mm — CS2KZ README: SQL_MM v1.3.4.2+
ARG SQL_MM_TAG=1.3.4.2
ARG SQL_MM_FILE=package-linux.tar.gz
ARG SQL_MM_SHA256=e0587e682994e99ccb801c124afd2f53d175f7e73fc81568bf9ed2f966333fd5

RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates curl \
	&& rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/bb-cs2-plugins \
	&& curl -fsSL "https://github.com/alliedmodders/metamod-source/releases/download/${METAMOD_TAG}/${METAMOD_FILE}" -o "/opt/bb-cs2-plugins/${METAMOD_FILE}" \
	&& echo "${METAMOD_SHA256}  /opt/bb-cs2-plugins/${METAMOD_FILE}" | sha256sum -c - \
	&& curl -fsSL "https://github.com/KZGlobalTeam/cs2kz-metamod/releases/download/${CS2KZ_TAG}/${CS2KZ_FILE}" -o "/opt/bb-cs2-plugins/${CS2KZ_FILE}" \
	&& echo "${CS2KZ_SHA256}  /opt/bb-cs2-plugins/${CS2KZ_FILE}" | sha256sum -c - \
	&& curl -fsSL "https://github.com/zer0k-z/sql_mm/releases/download/${SQL_MM_TAG}/${SQL_MM_FILE}" \
		-o "/opt/bb-cs2-plugins/sql_mm-linux.tar.gz" \
	&& echo "${SQL_MM_SHA256}  /opt/bb-cs2-plugins/sql_mm-linux.tar.gz" | sha256sum -c - \
	&& chown -R 1000:1000 /opt/bb-cs2-plugins

COPY cfg/cs2kz-server-config.biobase.txt /opt/bb-cs2-plugins/cs2kz-server-config.biobase.txt

COPY pre.sh /etc/pre.sh
RUN chmod 755 /etc/pre.sh

USER 1000:1000
