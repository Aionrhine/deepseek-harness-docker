#!/bin/sh
# Container entrypoint for the image.
#
# 1) Point the Web relay at the default-route interface: Docker publishes ports
#    (DNAT) toward that interface, so the relay must listen there.
# 2) Optionally start a key-only sshd when the binary exists.
# 3) Hand over to the upstream entrypoint with the original CMD arguments.
set -e

iface=$(awk '$2 == "00000000" { print $1; exit }' /proc/net/route)
if [ -n "$iface" ]; then
  export DSH_WEB_RELAY_INTERFACE="$iface"
fi

start_sshd() {
  [ "${DSH_SSHD_ENABLED:-1}" = "1" ] || return 0
  [ -x /usr/sbin/sshd ] || return 0
  keydir="${DSH_HOME:-/home/node/.dsh}/ssh"
  mkdir -p "$keydir"

  # Seed authorized_keys once from the deployment environment.
  if [ ! -s "$keydir/authorized_keys" ] && [ -n "${DSH_SSH_AUTHORIZED_KEY:-}" ]; then
    printf '%b\n' "${DSH_SSH_AUTHORIZED_KEY}" > "$keydir/authorized_keys"
    chmod 600 "$keydir/authorized_keys"
    echo "sshd: authorized_keys seeded from DSH_SSH_AUTHORIZED_KEY" >&2
  fi

  if [ ! -f "$keydir/ssh_host_ed25519_key" ]; then
    ssh-keygen -q -t ed25519 -N "" -f "$keydir/ssh_host_ed25519_key" \
      || { echo "sshd: host key generation failed" >&2; return 0; }
  fi
  chmod 600 "$keydir/ssh_host_ed25519_key" 2>/dev/null || true

  if [ ! -s "$keydir/authorized_keys" ]; then
    return 0
  fi

  cat > /tmp/sshd_config <<CONF
Port 2222
ListenAddress 0.0.0.0
HostKey $keydir/ssh_host_ed25519_key
AuthorizedKeysFile $keydir/authorized_keys
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
UsePAM no
PidFile none
StrictModes no
AllowUsers node
Subsystem sftp internal-sftp
CONF
  /usr/sbin/sshd -f /tmp/sshd_config -E /tmp/sshd.log \
    || { echo "sshd: failed to start (see /tmp/sshd.log)" >&2; return 0; }
  echo "sshd: listening on 0.0.0.0:2222" >&2
}

start_sshd

exec /usr/bin/tini -- /usr/local/bin/deepseek-harness-entrypoint "$@"
