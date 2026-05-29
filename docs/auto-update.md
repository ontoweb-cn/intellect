# Auto-update design & operations

This document describes how Intellect distributes update information and how each
release platform consumes it. The guiding policy is **notify + confirm**: the
system tells the user a newer version exists, but never applies an update
silently — the user explicitly confirms.

> **Status:** Phase 1 implemented = **containers** (Docker / Kubernetes) +
> the signed release **manifest**. Native-binary self-update (macOS/Linux/WSL2)
> is a later phase and will consume the same manifest.

## Design decisions

| Topic | Decision |
|------|----------|
| Hosting | **Gitee** primary now; Gitee + GitHub later (manifest carries both mirrors) |
| Signing | **minisign** (key-based, offline-verifiable, works regardless of host) |
| Automation | **Notify only — user confirms.** No silent auto-apply. |
| Channels | Single `stable` channel (no beta) |
| Layout | In-place / image-tag updates (no `releases/ + current` symlink scheme) |
| First platform | **Containers** (Docker Compose + Kubernetes) |

## The release manifest

Every release publishes a signed manifest as a Gitee/GitHub Release asset:

- `update.json` — machine-readable description of the latest release
- `update.json.minisig` — its minisign signature

### Schema (`schema: 1`)

```jsonc
{
  "schema": 1,
  "channel": "stable",
  "version": "v0.15.0",
  "released": "2026-05-29",
  "min_supported": "v0.13.0",          // optional: below this, prompt to upgrade
  "notes": "Human-readable highlights", // optional
  "artifacts": {
    "docker": {
      "agent": { "image": "docker.io/ontoweb/intellect-agent", "tag": "0.15.0" },
      "webui": { "image": "docker.io/ontoweb/intellect-webui", "tag": "0.15.0" }
    },
    // Native entries are added in a later phase, e.g.:
    "linux-amd64": { "url": "https://gitee.com/.../intellect-dist-linux-amd64-v0.15.0.tar.gz",
                     "sha256": "…", "size": 12345678 }
  },
  "mirrors": [
    "https://gitee.com/ontoweb/intellect/releases/download/v0.15.0",
    "https://github.com/ontoweb-cn/intellect/releases/download/v0.15.0"
  ]
}
```

### Generating & signing

`scripts/gen-manifest.sh` builds and signs the manifest; `scripts/release.sh`
calls it automatically and uploads `update.json` + `update.json.minisig` to the
Gitee and GitHub releases alongside the other assets.

```bash
# Standalone (also picks up any native tarballs already in dist/)
MINISIGN_SECRET_KEY=~/.minisign/intellect.key \
  ./scripts/gen-manifest.sh --version v0.15.0
```

If no key (or `minisign`) is available the manifest is still written but
**unsigned**, with a warning.

## Signing key management (minisign)

1. **Generate a release keypair once** (use a passwordless key for CI so signing
   is non-interactive):

   ```bash
   minisign -G -W -p intellect.pub -s intellect.key
   ```

2. **Commit the public key** to `assets/minisign.pub` (replace the placeholder).
   It ships inside images/binaries so clients can verify offline.

3. **Store the secret key** (`intellect.key`) as a CI secret and expose it to the
   release job as `MINISIGN_SECRET_KEY` (a path). Never commit the secret key.

4. **Verify a manifest manually:**

   ```bash
   minisign -Vm update.json -p assets/minisign.pub
   ```

`gen-manifest.sh` self-verifies the freshly-signed manifest against
`assets/minisign.pub` (once the placeholder is replaced) and fails on mismatch.

## Containers — notify + confirm

In containers the WebUI's git-based self-update does not apply (no `.git`).
Updates are driven by watching the registry for the tags the manifest points to,
and the **confirm** step is a one-liner you run yourself:

```bash
cd docker
docker compose pull && docker compose up -d
```

### Docker Compose — Diun (recommended, notify-only)

[Diun](https://crazymax.dev/diun/) only notifies; it never pulls or restarts.

```bash
docker compose -f docker-compose.yml -f docker-compose.diun.yml up -d
docker logs intellect-diun            # see detected updates
```

See `docker/docker-compose.diun.yml` for notifier options (Telegram/Slack/...).

### Docker Compose — Watchtower (monitor-only alternative)

```bash
docker compose -f docker-compose.yml -f docker-compose.watchtower.yml up -d
docker logs intellect-watchtower
```

`WATCHTOWER_MONITOR_ONLY=true` keeps it notify-only. See
`docker/docker-compose.watchtower.yml`.

### Kubernetes — Keel with manual approval

See `k8s/keel/README.md`: Keel polls the registry and requires a manual
**approval** before rolling out — the cluster-native "confirm".

## Roadmap (later phases)

- **Native binaries (macOS/Linux/WSL2):** extend `intellect update` to, for the
  "native binary" install method, read this manifest, download the platform
  tarball from a mirror, verify `sha256` + minisign, replace `bin/`+`webui/`
  in place, and restart via `ctl.sh` — still notify + confirm.
- **GitHub mirror:** publish the manifest + assets to GitHub releases too (the
  `mirrors` list already advertises both); clients fall back across mirrors.
- **In-app banner everywhere:** optionally repoint the WebUI `/api/updates/check`
  and the agent banner to this manifest so the existing notification UI also
  works in Docker (currently git-only). *(Requires changes in the
  intellect-webui / intellect-agent repos — out of scope for this phase.)*
