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

RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates curl \
	&& rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/bb-cs2-plugins \
	&& curl -fsSL "https://github.com/alliedmodders/metamod-source/releases/download/${METAMOD_TAG}/${METAMOD_FILE}" -o "/opt/bb-cs2-plugins/${METAMOD_FILE}" \
	&& echo "${METAMOD_SHA256}  /opt/bb-cs2-plugins/${METAMOD_FILE}" | sha256sum -c - \
	&& curl -fsSL "https://github.com/KZGlobalTeam/cs2kz-metamod/releases/download/${CS2KZ_TAG}/${CS2KZ_FILE}" -o "/opt/bb-cs2-plugins/${CS2KZ_FILE}" \
	&& echo "${CS2KZ_SHA256}  /opt/bb-cs2-plugins/${CS2KZ_FILE}" | sha256sum -c - \
	&& chown -R 1000:1000 /opt/bb-cs2-plugins

COPY pre.sh /etc/pre.sh
RUN chmod 755 /etc/pre.sh

USER 1000:1000
