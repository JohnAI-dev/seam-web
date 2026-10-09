#!/usr/bin/env bash
# Move seam-web on prod1 into isolated, rootless containers and remove everything the
# first setup script put directly on the host.
#
# Run on prod1 as a user with sudo:
#   bash prod1-migrate.sh
# Safe to re-run; it converges to the setup below.
#
# Result:
#   - user "seam" (no password, no sudo) owns everything below
#   - one rootless Podman pod "seam-web" with two containers:
#       web:    unprivileged nginx serving the site, published ONLY on 127.0.0.1:8081
#       puller: every minute downloads the tested `live` branch of the public repo and
#               publishes it. Nothing ever connects TO prod1; it can only write the site folder.
#   - Cloudflare Tunnel points seamweb.no at http://localhost:8081
#   - nginx, the old runner service, its user and /var/www/seam-web are removed from the host
set -euo pipefail
# Commands run as the 'seam' user, who can't enter your home folder; work from / instead.
cd /

SEAM_USER=seam
REPO_URL=https://github.com/JohnAI-dev/seam-web
WEB_IMAGE=docker.io/nginxinc/nginx-unprivileged:stable-alpine
PULLER_IMAGE=docker.io/library/alpine:3

say() { echo; echo "== $*"; }

say "1/5 Podman"
command -v podman >/dev/null || sudo pacman -S --needed --noconfirm podman

say "2/5 User '$SEAM_USER' (no login password, no sudo)"
if ! id "$SEAM_USER" >/dev/null 2>&1; then
  sudo useradd --create-home --shell /usr/bin/nologin "$SEAM_USER"
fi
grep -q "^$SEAM_USER:" /etc/subuid || sudo usermod --add-subuids 200000-265535 --add-subgids 200000-265535 "$SEAM_USER"
sudo loginctl enable-linger "$SEAM_USER"
SEAM_UID=$(id -u "$SEAM_USER")
SEAM_HOME=$(getent passwd "$SEAM_USER" | cut -d: -f6)
for _ in $(seq 1 20); do [ -d "/run/user/$SEAM_UID" ] && break; sleep 0.5; done
as_seam() { sudo -u "$SEAM_USER" XDG_RUNTIME_DIR="/run/user/$SEAM_UID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$SEAM_UID/bus" "$@"; }

say "3/5 Site folder and container definitions"
as_seam mkdir -p "$SEAM_HOME/site" "$SEAM_HOME/.config/containers/systemd"
# Keep the site online during the move: start from what is deployed today.
if [ -d /var/www/seam-web ] && [ -z "$(ls -A "$SEAM_HOME/site" 2>/dev/null)" ]; then
  sudo cp -a /var/www/seam-web/. "$SEAM_HOME/site/"
  sudo chown -R "$SEAM_USER:$SEAM_USER" "$SEAM_HOME/site"
fi
as_seam chmod 755 "$SEAM_HOME/site"

Q="$SEAM_HOME/.config/containers/systemd"
as_seam tee "$Q/seam-web.pod" >/dev/null <<EOF
[Pod]
PodName=seam-web
# Only reachable from prod1 itself; Cloudflare Tunnel connects to it.
PublishPort=127.0.0.1:8081:8080
EOF
as_seam tee "$Q/seam-web-site.container" >/dev/null <<EOF
[Unit]
Description=seamweb.no static site

[Container]
Image=$WEB_IMAGE
Pod=seam-web.pod
Volume=$SEAM_HOME/site:/usr/share/nginx/html:ro,Z
ReadOnly=true
Tmpfs=/tmp
DropCapability=ALL
NoNewPrivileges=true

[Service]
Restart=always

[Install]
WantedBy=default.target
EOF
as_seam tee "$SEAM_HOME/puller.sh" >/dev/null <<'PULLER'
#!/bin/sh
# Publish the tested `live` branch of seam-web. Keeps the current site if anything fails.
URL=https://codeload.github.com/JohnAI-dev/seam-web/tar.gz/refs/heads/live
while true; do
  tmp=$(mktemp -d)
  if wget -q -T 30 -O "$tmp/live.tgz" "$URL" && tar -xzf "$tmp/live.tgz" -C "$tmp"; then
    new=$(ls -d "$tmp"/*/site 2>/dev/null | head -1)
    if [ -n "$new" ] && [ -f "$new/index.html" ]; then
      if ! diff -r -q "$new" /site >/dev/null 2>&1; then
        find /site -mindepth 1 -delete && cp -a "$new"/. /site/ && echo "$(date -u) published new version"
      fi
    else
      echo "$(date -u) download has no site/index.html; keeping current site"
    fi
  else
    echo "$(date -u) could not fetch the live branch (repo private or branch missing?); keeping current site"
  fi
  rm -rf "$tmp"
  sleep 60
done
PULLER
as_seam tee "$Q/seam-web-puller.container" >/dev/null <<UNIT
[Unit]
Description=Publishes the tested live branch of seam-web

[Container]
Image=$PULLER_IMAGE
Pod=seam-web.pod
Exec=sh /puller.sh
Volume=$SEAM_HOME/puller.sh:/puller.sh:ro,Z
Volume=$SEAM_HOME/site:/site:Z
ReadOnly=true
Tmpfs=/tmp
DropCapability=ALL
NoNewPrivileges=true

[Service]
Restart=always

[Install]
WantedBy=default.target
UNIT
# Remove the earlier runner container, if this prod1 had one.
if [ -f "$Q/seam-web-runner.container" ]; then
  as_seam systemctl --user stop seam-web-runner.service 2>/dev/null || true
  as_seam rm -f "$Q/seam-web-runner.container"
  as_seam podman volume rm -f seam-runner-state >/dev/null 2>&1 || true
  echo "removed the runner container (also delete 'prod1-seam-web' under Settings → Actions → Runners)"
fi
as_seam rm -rf "$SEAM_HOME/runner"

say "4/5 Start the containers"
as_seam podman pull -q "$WEB_IMAGE" "$PULLER_IMAGE" >/dev/null
as_seam systemctl --user daemon-reload
as_seam systemctl --user restart seam-web-pod.service
for _ in $(seq 1 30); do curl -fsS -o /dev/null http://127.0.0.1:8081/ && break; sleep 1; done
curl -fsS http://127.0.0.1:8081/ | grep -q "<title>" \
  && echo "site container answers on 127.0.0.1:8081" \
  || { echo "site container is not answering; nothing on the host has been removed"; exit 1; }

say "5/5 Remove what the first setup put on the host"
if systemctl list-units --all --plain --no-legend | grep -q 'actions.runner.JohnAI-dev-seam-web'; then
  (cd /opt/actions-runner/seam-web && sudo ./svc.sh stop && sudo ./svc.sh uninstall) || true
fi
sudo rm -rf /opt/actions-runner/seam-web
sudo rmdir /opt/actions-runner 2>/dev/null || true
id github-runner >/dev/null 2>&1 && sudo userdel --remove github-runner 2>/dev/null || true
# nginx was installed by the first setup script today (only site: seam-web). Remove it
# only if that is still true, so we never touch an nginx you use for something else.
if pacman -Qi nginx >/dev/null 2>&1; then
  others=$(ls /etc/nginx/conf.d 2>/dev/null | grep -v '^seam-web.conf$' || true)
  installed=$(LC_ALL=C pacman -Qi nginx | sed -n 's/^Install Date *: //p')
  if [ -z "$others" ] && [ -f /etc/nginx/nginx.conf.orig ]; then
    echo "removing nginx (installed $installed, served only seam-web)"
    sudo systemctl disable --now nginx
    sudo pacman -Rns --noconfirm nginx
    sudo rm -rf /etc/nginx
  else
    echo "nginx serves other sites; only removing the seam-web part"
    sudo rm -f /etc/nginx/conf.d/seam-web.conf
    [ -f /etc/nginx/nginx.conf.orig ] && sudo mv /etc/nginx/nginx.conf.orig /etc/nginx/nginx.conf
    sudo nginx -t && sudo systemctl reload nginx
  fi
fi
sudo rm -rf /var/www/seam-web
sudo rmdir /var/www 2>/dev/null || true

echo
echo "Done. Containers: sudo -u $SEAM_USER XDG_RUNTIME_DIR=/run/user/$SEAM_UID podman ps"
echo "Next: in your Cloudflare Tunnel, point seamweb.no and www.seamweb.no at http://localhost:8081"
echo "Remove everything later with:"
echo "  sudo loginctl disable-linger $SEAM_USER && sudo userdel --remove $SEAM_USER"
