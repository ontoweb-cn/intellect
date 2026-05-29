# Kubernetes auto-update with Keel (notify + manual approval)

[Keel](https://keel.sh) watches the registry for new image tags and, with
**approvals enabled**, will *not* roll out an update until a human approves it —
matching the project's "notify + confirm" policy. Without approvals Keel would
auto-update; the annotations below intentionally require an approval.

## 1. Install Keel

```bash
helm repo add keel https://charts.keel.sh
helm repo update
helm upgrade --install keel keel/keel \
  --namespace keel --create-namespace \
  --set approvals.enabled=true \
  --set helmProvider.enabled=false
```

(Optionally enable the Keel web UI / Slack / MS Teams approval bots — see the
Keel docs. Approvals can be granted via the Keel UI, `kubectl`, or chat-ops.)

## 2. Annotate the Intellect workloads

These annotations make Keel poll the registry every 6h and require **1 manual
approval** before applying a new image:

```bash
kubectl -n intellect annotate statefulset/intellect-agent \
  keel.sh/policy=force \
  keel.sh/trigger=poll \
  keel.sh/pollSchedule="@every 6h" \
  keel.sh/approvals="1" \
  --overwrite

kubectl -n intellect annotate deployment/intellect-webui \
  keel.sh/policy=force \
  keel.sh/trigger=poll \
  keel.sh/pollSchedule="@every 6h" \
  keel.sh/approvals="1" \
  --overwrite
```

- `keel.sh/policy=force` — track the floating tag (e.g. `latest` or a moving
  release tag). Use `major`/`minor`/`patch` instead if you pin semver tags.
- `keel.sh/approvals="1"` — **the confirm step**: nothing is rolled out until
  one approval is granted.

## 3. Approve an update

When Keel detects a newer image it creates a pending approval. List and approve:

```bash
kubectl get approvals -n keel
# Approve via the Keel UI, or the approval bot, or the Keel CLI/API.
```

## Notes

- This is **opt-in** and lives outside the shipped manifests so the base
  `k8s/manifests/` stay update-tool-agnostic.
- The signed release manifest (`update.json`, see `docs/auto-update.md`) remains
  the source of truth for "what is the latest version"; Keel complements it by
  watching the registry tags that the manifest points to.
- To remove auto-update, delete the annotations:
  `kubectl -n intellect annotate statefulset/intellect-agent keel.sh/policy- keel.sh/trigger- keel.sh/pollSchedule- keel.sh/approvals-`
