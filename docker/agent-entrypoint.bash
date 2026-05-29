#!/bin/bash
# Entrypoint for binary-only agent images. Same bootstrap as docker/entrypoint.sh
# but runs the Nuitka-compiled `intellect` binary instead of a venv + source tree.
set -e

INTELLECT_HOME="${INTELLECT_HOME:-/opt/data}"
INSTALL_DIR="/opt/intellect"

export PATH="${INSTALL_DIR}/bin:${PATH}"
export INTELLECT_BUNDLED_SKILLS="${INTELLECT_BUNDLED_SKILLS:-${INSTALL_DIR}/skills}"

if [ "$(id -u)" = "0" ]; then
    if [ -n "$INTELLECT_UID" ] && [ "$INTELLECT_UID" != "$(id -u intellect)" ]; then
        usermod -u "$INTELLECT_UID" intellect
    fi
    if [ -n "$INTELLECT_GID" ] && [ "$INTELLECT_GID" != "$(id -g intellect)" ]; then
        groupmod -o -g "$INTELLECT_GID" intellect 2>/dev/null || true
    fi

    actual_intellect_uid=$(id -u intellect)
    needs_chown=false
    if [ -n "$INTELLECT_UID" ] && [ "$INTELLECT_UID" != "10000" ]; then
        needs_chown=true
    elif [ "$(stat -c %u "$INTELLECT_HOME" 2>/dev/null)" != "$actual_intellect_uid" ]; then
        needs_chown=true
    fi
    if [ "$needs_chown" = true ]; then
        chown -R intellect:intellect "$INTELLECT_HOME" 2>/dev/null || \
            echo "Warning: chown $INTELLECT_HOME failed (rootless?) — continuing"
    fi

    if [ -f "$INTELLECT_HOME/config.yaml" ]; then
        chown intellect:intellect "$INTELLECT_HOME/config.yaml" 2>/dev/null || true
        chmod 640 "$INTELLECT_HOME/config.yaml" 2>/dev/null || true
    fi

    exec gosu intellect "$0" "$@"
fi

mkdir -p "$INTELLECT_HOME"/{cron,sessions,logs,hooks,memories,skills,skins,plans,workspace,home}

if [ ! -f "$INTELLECT_HOME/.env" ]; then
    cp "$INSTALL_DIR/.env.example" "$INTELLECT_HOME/.env"
fi
if [ ! -f "$INTELLECT_HOME/config.yaml" ]; then
    cp "$INSTALL_DIR/cli-config.yaml.example" "$INTELLECT_HOME/config.yaml"
fi
if [ ! -f "$INTELLECT_HOME/SOUL.md" ]; then
    cp "$INSTALL_DIR/docker/SOUL.md" "$INTELLECT_HOME/SOUL.md"
fi
if [ ! -f "$INTELLECT_HOME/auth.json" ] && [ -n "$INTELLECT_AUTH_JSON_BOOTSTRAP" ]; then
    printf '%s' "$INTELLECT_AUTH_JSON_BOOTSTRAP" > "$INTELLECT_HOME/auth.json"
    chmod 600 "$INTELLECT_HOME/auth.json"
fi

# `intellect` syncs bundled skills on every launch (see intellect_cli/main.py).
if [ $# -gt 0 ] && command -v "$1" >/dev/null 2>&1; then
    exec "$@"
fi
exec intellect "$@"
