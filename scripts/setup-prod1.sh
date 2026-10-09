#!/usr/bin/env bash
# One-time setup of prod1 for seam-web. Run on prod1 as a user with sudo:
#   RUNNER_TOKEN=<token from GitHub> bash setup-prod1.sh
# Get RUNNER_TOKEN from: github.com/JohnAI-dev/seam-web/settings/actions/runners/new
# (it is short-lived, ~1 hour; it is NOT your personal access token).
set -euo pipefail
: "${RUNNER_TOKEN:?set RUNNER_TOKEN first}"
REPO_URL="https://github.com/JohnAI-dev/seam-web"
RUNNER_USER=github-runner
RUNNER_DIR=/opt/actions-runner/seam-web

echo "== packages"
if command -v apt-get >/dev/null; then
  sudo apt-get update -qq && sudo apt-get install -y -qq nginx rsync curl jq tar git python3
elif command -v dnf >/dev/null; then
  sudo dnf install -y -q nginx rsync curl jq tar git python3
else
  echo "Unsupported distro: install nginx rsync curl jq git python3 manually"; exit 1
fi

echo "== runner user and web root"
id "$RUNNER_USER" >/dev/null 2>&1 || sudo useradd --system --create-home --shell /bin/bash "$RUNNER_USER"
sudo mkdir -p /var/www/seam-web
sudo chown -R "$RUNNER_USER":"$RUNNER_USER" /var/www/seam-web

echo "== nginx site"
sudo tee /etc/nginx/conf.d/seam-web.conf >/dev/null <<'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    root /var/www/seam-web;
    index index.html;
    location / { try_files $uri $uri/ =404; }
}
NGINX
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl enable --now nginx && sudo systemctl reload nginx

echo "== GitHub Actions runner"
case "$(uname -m)" in
  x86_64) ARCH=x64 ;; aarch64|arm64) ARCH=arm64 ;; *) echo "unsupported arch"; exit 1 ;;
esac
VER=$(curl -fsS https://api.github.com/repos/actions/runner/releases/latest | jq -r .tag_name | sed 's/^v//')
sudo mkdir -p "$RUNNER_DIR" && sudo chown "$RUNNER_USER":"$RUNNER_USER" "$RUNNER_DIR"
sudo -u "$RUNNER_USER" bash -c "cd $RUNNER_DIR && \
  curl -fsSL -o runner.tgz https://github.com/actions/runner/releases/download/v$VER/actions-runner-linux-$ARCH-$VER.tar.gz && \
  tar xzf runner.tgz && rm runner.tgz && \
  ./config.sh --unattended --replace --url $REPO_URL --token $RUNNER_TOKEN --name prod1-seam-web --labels prod1"
cd "$RUNNER_DIR" && sudo ./svc.sh install "$RUNNER_USER" && sudo ./svc.sh start

echo "== done. Runner 'prod1-seam-web' should now show as Idle on GitHub."
