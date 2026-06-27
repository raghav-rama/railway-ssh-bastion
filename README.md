# Railway SSH Bastion

This project runs a small SSH bastion on Railway so you can reach a private Ubuntu laptop over a reverse SSH tunnel. Railway is the public jump host; the Ubuntu laptop calls out to Railway and keeps the tunnel open.

Flow:

`your client -> Railway bastion -> reverse tunnel -> Ubuntu laptop:22`

## Why this is SSH-only

Railway is a workable TCP jump host, not a full VPS replacement for WireGuard. This image intentionally does not install or configure WireGuard or UFW. The container only runs:

- `sshd` on port `2222` for the public bastion entrypoint
- `caddy` on `${PORT}` for Railway health checks

The existing `wg0.conf` file in this directory is unused by this setup.

## Environment

Set these Railway environment variables:

- `ADMIN_AUTHORIZED_KEYS`: one or more newline-separated SSH public keys for your own bastion login
- `LAPTOP_TUNNEL_PUBLIC_KEY`: the public key used by the Ubuntu laptop to open the reverse tunnel
- `PORT`: Railway injects this automatically for the HTTP health endpoint

## Railway setup

1. Deploy this directory as a Docker service.
2. Add `ADMIN_AUTHORIZED_KEYS` and `LAPTOP_TUNNEL_PUBLIC_KEY`.
3. Configure a Railway TCP Proxy to forward the public SSH endpoint to container port `2222`.
4. Keep the service HTTP port on `${PORT}` so Railway can reach `/health`.
5. Verify the health endpoint:

```bash
curl https://<your-railway-domain>/health
```

## Ubuntu laptop setup

Generate a dedicated tunnel keypair on the Ubuntu laptop:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/railway-tunnel -C railway-tunnel
cat ~/.ssh/railway-tunnel.pub
```

Put the public key value into `LAPTOP_TUNNEL_PUBLIC_KEY`.

Create a `systemd` unit at `/etc/systemd/system/railway-reverse-ssh.service`:

```ini
[Unit]
Description=Reverse SSH tunnel to Railway bastion
After=network-online.target
Wants=network-online.target

[Service]
User=<ubuntu-username>
ExecStart=/usr/bin/ssh -NT \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -o StrictHostKeyChecking=accept-new \
  -i /home/<ubuntu-username>/.ssh/railway-tunnel \
  -R localhost:2201:localhost:22 \
  railway@<railway-tcp-proxy-host> -p <railway-tcp-proxy-port>
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Enable and start it:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now railway-reverse-ssh.service
sudo systemctl status railway-reverse-ssh.service
```

## Client SSH config

Add entries like these to your local `~/.ssh/config`:

```sshconfig
Host railway-bastion
  HostName <railway-tcp-proxy-host>
  Port <railway-tcp-proxy-port>
  User railway
  IdentityFile ~/.ssh/<your-admin-key>

Host ubuntu-laptop-via-railway
  HostName localhost
  Port 2201
  User <ubuntu-username>
  ProxyJump railway-bastion
```

Then connect with:

```bash
ssh railway-bastion
ssh ubuntu-laptop-via-railway
```

## Local smoke test

Run:

```bash
bash tests/smoke.sh
```

The smoke test builds the image, verifies startup fails without the required env vars, checks `/health`, confirms key-based SSH access works, verifies password auth is disabled, and inspects the restricted tunnel key entry.
