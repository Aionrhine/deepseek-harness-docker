# Deployment guide

Image: `ghcr.io/aionrhine/deepseek-harness` — community packaging of
`@deepseek-ai/dsh`, built from this fork. Multi-arch (`linux/amd64`, `linux/arm64`).

## Prerequisites

- Docker Engine 24+ with Compose v2
- About 3.5 GB for the image, plus the volume for your workspace
- No registry login needed: the package is public

## Quick start

```bash
mkdir -p /opt/deepseek-harness/data/{dsh-home,workspace}
cd /opt/deepseek-harness

# copy compose.yaml and .env.example from this directory
cp deploy/compose.yaml docker-compose.yml
cp deploy/.env.example .env

docker compose pull
docker compose up -d
docker compose ps          # wait for "healthy"
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3080/   # expect 401
```

Open `http://127.0.0.1:3080`. The first request without a session cookie returns
401 by design; the launch token is printed in the logs:

```bash
docker compose logs deepseek-harness | grep 'dsh web:'
```

Open the URL from that line once (it carries `?token=...`), which sets the browser
cookie. From then on the plain URL works.

## Environment reference

| Variable | Default | Meaning |
| --- | --- | --- |
| `DSH_IMAGE_REPOSITORY` | `ghcr.io/aionrhine/deepseek-harness` | image repository |
| `DSH_IMAGE_VERSION` | `0.2.2-rc.1-r1` | immutable tag, never `latest` |
| `DSH_BIND_ADDRESS` | `127.0.0.1` | host interface both ports bind to |
| `DSH_WEB_PORT` | `3080` | host port for the Web UI |
| `DSH_SSH_PORT` | `2222` | host port for the optional sshd |
| `DSH_SSH_AUTHORIZED_KEY` | empty | public key(s) for sshd; empty disables it |
| `DSH_DESKTOP_ENABLED` | `0` | `1` starts the virtual desktop + Chromium |
| `DSH_BROWSER_USE_ENABLED` | `0` | `1` lets the model drive the browser (needs desktop) |

## Data

Two bind mounts:

- `./data/dsh-home` → `/home/node/.dsh` — profile, plugins, settings, credentials,
  sessions, ssh keys
- `./data/workspace` → `/workspace` — the agent's working directory

Back up `data/dsh-home` before any upgrade. The image never stores state; deleting
the container loses nothing.

## Optional SSH

Set a public key and the container starts a key-only sshd on port 2222:

```dotenv
DSH_SSH_AUTHORIZED_KEY=ssh-ed25519 AAAAC3Nza... you@laptop
```

```bash
docker compose up -d
ssh -p 2222 node@127.0.0.1
```

The host key is generated on first start inside `data/dsh-home/ssh` and keeps its
fingerprint across container rebuilds. Remove `DSH_SSH_AUTHORIZED_KEY` (and the
file in the volume) to disable sshd. Never expose this port publicly: it is a
full shell inside the container.

## Upgrades

```bash
sed -i 's/^DSH_IMAGE_VERSION=.*/DSH_IMAGE_VERSION=0.2.2-rc.1-r2/' .env
docker compose pull
docker compose up -d
docker compose ps
```

Rollback is the same command with the previous tag; images are immutable so tags
never silently change under you.

Major-version jumps may require re-installing plugins whose `engines.dsh` no
longer matches. The plugin list lives in
`data/dsh-home/profiles/web/package.json`.

## Security notes

- Defaults bind to `127.0.0.1`. Put a private network (WireGuard/Tailscale) or an
  authenticating HTTPS proxy in front before exposing it.
- The Web UI can execute code through agent tools. Treat access to it as access to
  the container and the mounted workspace.
- `read_only: true`, `cap_drop: ALL` and `no-new-privileges` are set in the example.
  Keep them.
- The agent sandbox needs a kernel with Landlock. On hosts without it, DSH falls
  back to bubblewrap, which requires `seccomp=unconfined` and
  `systempaths=unconfined` in the service definition.

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| container exits immediately | check `docker compose logs`; usually a bad volume permission (data must be writable by uid 1000) |
| `401` forever after opening the URL | open the token URL from the logs once |
| "重新连接中" in the UI | the browser reached the page through a proxy; the WebSocket to `/api` failed |
| sshd not listening | `DSH_SSH_AUTHORIZED_KEY` empty, or the key line is malformed |
| agent cannot run commands | kernel without Landlock and bwrap not enabled |

Volume permission fix:

```bash
sudo chown -R 1000:1000 /opt/deepseek-harness/data
```
