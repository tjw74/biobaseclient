# mDNS: `biobase.local` on the LAN (Avahi)

This stack **only adds**:

1. A long-running `avahi-publish` process that registers **`biobase.local`** → this host’s **LAN IPv4** (restarts if it dies).  
2. An optional file under **`/etc/avahi/services/`** that advertises **`_http._tcp`** on the **Biobase gateway port** (default 8880) for discovery UIs.  

It does **not** modify **`/etc/avahi/avahi-daemon.conf`**, your machine hostname, or any other mDNS / Avahi data files except installing **`/etc/avahi/services/bb-biobase-hub.service`** (a unique new file).

## One-time install (on the Docker host)

```bash
cd bb_biobase_local/mdns
sudo BIOBASE_LOCAL_PORT=8880 ./install-biobase-mdns.sh
```

Match **`BIOBASE_LOCAL_PORT`** to the host port in `../docker-compose` (`BIOBASE_LOCAL_PORT`, default 8880).

## Optional: pin IP or name

- Copy and edit: **`/etc/default/biobase-mdns`** (from `biobase-mdns.default` if the installer created it)  
- Set **`BIOBASE_LOCAL_IP=`** or **`BIOBASE_MDNS_NAME=`** (single label, default `biobase` → `biobase.local`)  
- `sudo systemctl restart biobase-mdns.service`

## Then

Use **`http://biobase.local:8880/`** on the same LAN (client must support mDNS, e.g. macOS, most Linux with `avahi` / `systemd-resolved`).

## Remove

```bash
sudo systemctl disable --now biobase-mdns.service
sudo rm -f /usr/local/bin/biobase-mdns-publish /etc/systemd/system/biobase-mdns.service /etc/avahi/services/bb-biobase-hub.service
sudo systemctl daemon-reload
sudo systemctl reload avahi-daemon || sudo systemctl restart avahi-daemon
```

(Leaves `/etc/default/biobase-mdns` for you to delete if desired.)
