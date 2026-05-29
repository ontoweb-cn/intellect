#!/bin/bash
# Slim entrypoint for binary-only WebUI images (static/ + intellect-webui binary).
# Based on intellect-webui/docker_init.bash — keeps UID/GID alignment and env
# propagation, skips venv/runtime pip (deps are baked into the Nuitka binary).
set -e

error_exit() {
  echo "!! ERROR: $*"
  exit 1
}

export ENV_IGNORELIST="HOME PWD USER SHLVL TERM OLDPWD SHELL _ SUDO_COMMAND HOSTNAME LOGNAME MAIL SUDO_GID SUDO_UID SUDO_USER CHECK_NV_CUDNN_VERSION VIRTUAL_ENV VIRTUAL_ENV_PROMPT ENV_IGNORELIST ENV_OBFUSCATE_PART"
export ENV_OBFUSCATE_PART="TOKEN API KEY"

whoami=$(whoami 2>/dev/null || echo "uid-$(id -u)")
script_fullname=$0
umask 0077

itdir=/tmp/intellectwebui_init
if [ "A${whoami}" == "Aroot" ]; then
  mkdir -p "$itdir"
  chmod 700 "$itdir"
else
  mkdir -p "$itdir" 2>/dev/null || itdir="/app/.intellectwebui_init"
  mkdir -p "$itdir"
fi

write_privtmpfile() {
  printf '%s' "$2" > "$1"
  chmod 600 "$1"
}

# ── UID/GID alignment (same logic as docker_init.bash) ─────────────────────
it=$itdir/intellectwebui_user_uid
if [ -z "${WANTED_UID+x}" ] && [ -f "$it" ]; then WANTED_UID=$(cat "$it"); fi
if [ -z "${WANTED_UID+x}" ] || [ "${WANTED_UID}" = "1024" ]; then
  for _probe_dir in "/home/intellectwebui/.intellect" "$INTELLECT_HOME" "/opt/data"; do
    if [ -d "$_probe_dir" ]; then
      _detected_uid=$(stat -c '%u' "$_probe_dir" 2>/dev/null || echo "")
      if [ -n "$_detected_uid" ] && [ "$_detected_uid" != "0" ]; then
        WANTED_UID=$_detected_uid
        break
      fi
    fi
  done
fi
if [ -z "${WANTED_UID+x}" ] || [ "${WANTED_UID}" = "1024" ]; then
  if [ -d "/workspace" ]; then
    _detected_uid=$(stat -c '%u' "/workspace" 2>/dev/null || echo "")
    if [ -n "$_detected_uid" ] && [ "$_detected_uid" != "0" ]; then
      WANTED_UID=$_detected_uid
    fi
  fi
fi
WANTED_UID=${WANTED_UID:-1024}
write_privtmpfile "$it" "$WANTED_UID"

it=$itdir/intellectwebui_user_gid
if [ -z "${WANTED_GID+x}" ] && [ -f "$it" ]; then WANTED_GID=$(cat "$it"); fi
if [ -z "${WANTED_GID+x}" ] || [ "${WANTED_GID}" = "1024" ]; then
  for _probe_dir in "/home/intellectwebui/.intellect" "$INTELLECT_HOME" "/opt/data"; do
    if [ -d "$_probe_dir" ]; then
      _detected_gid=$(stat -c '%g' "$_probe_dir" 2>/dev/null || echo "")
      if [ -n "$_detected_gid" ] && [ "$_detected_gid" != "0" ]; then
        WANTED_GID=$_detected_gid
        break
      fi
    fi
  done
fi
if [ -z "${WANTED_GID+x}" ] || [ "${WANTED_GID}" = "1024" ]; then
  if [ -d "/workspace" ]; then
    _detected_gid=$(stat -c '%g' "/workspace" 2>/dev/null || echo "")
    if [ -n "$_detected_gid" ] && [ "$_detected_gid" != "0" ]; then
      WANTED_GID=$_detected_gid
    fi
  fi
fi
WANTED_GID=${WANTED_GID:-1024}
write_privtmpfile "$it" "$WANTED_GID"

save_env() {
  env | sort > "$1"
}

load_env() {
  tocheck=$1
  overwrite_if_different=$2
  if [ ! -f "$tocheck" ]; then return; fi
  while IFS='=' read -r key value; do
    doit=false
    for i in $ENV_IGNORELIST; do
      if [[ "A$key" == "A$i" ]]; then doit=ignore; break; fi
    done
    [[ "A$doit" == "Aignore" ]] && continue
    rvalue=$value
    if [ -z "${!key}" ]; then
      doit=true
    elif [ "A$overwrite_if_different" == "Atrue" ] && [[ "A${!key}" != "A${value}" ]]; then
      doit=true
    fi
    [[ "A$doit" == "Atrue" ]] && export "$key=$value"
  done < "$tocheck"
}

chown_home_intellectwebui() {
  find /home/intellectwebui \
    -path "/home/intellectwebui/.intellect/intellect-agent" -prune \
    -o -exec chown -h "${WANTED_UID}:${WANTED_GID}" {} +
}

if [ "A${whoami}" == "Aroot" ]; then
  _readonly_root=false
  if ! sh -c 'test -w /etc/group && test -w /etc/passwd' 2>/dev/null; then
    _readonly_root=true
  fi
  if [ "A${_readonly_root}" == "Atrue" ]; then
    _current_uid=$(id -u intellectwebui 2>/dev/null || echo "")
    _current_gid=$(id -g intellectwebui 2>/dev/null || echo "")
    if [ "A${_current_gid}" != "A${WANTED_GID}" ] || [ "A${_current_uid}" != "A${WANTED_UID}" ]; then
      error_exit "read-only root fs: set WANTED_UID/GID to match image user"
    fi
  else
    groupmod -o -g "${WANTED_GID}" intellectwebui || error_exit "groupmod failed"
    usermod -o -u "${WANTED_UID}" intellectwebui || error_exit "usermod failed"
  fi

  chown_home_intellectwebui || error_exit "chown /home/intellectwebui failed"
  mkdir -p /app || error_exit "mkdir /app failed"
  chown intellectwebui:intellectwebui /app || error_exit "chown /app failed"
  rsync -av --chown=intellectwebui:intellectwebui /apptoo/ /app/ || error_exit "rsync /apptoo -> /app failed"

  export INTELLECT_WEBUI_DEFAULT_WORKSPACE="${INTELLECT_WEBUI_DEFAULT_WORKSPACE:-/workspace}"
  mkdir -p "$INTELLECT_WEBUI_DEFAULT_WORKSPACE" 2>/dev/null || true
  chown intellectwebui:intellectwebui "$INTELLECT_WEBUI_DEFAULT_WORKSPACE" 2>/dev/null || true

  ENV_FILE="/tmp/intellectwebui_root_env.txt"
  if ! ( : > "$ENV_FILE" ) 2>/dev/null; then
    ENV_FILE="${itdir}/intellectwebui_root_env.txt"
  fi
  save_env "$ENV_FILE"
  chown "${WANTED_UID}:${WANTED_GID}" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  export _HW_ROOT_ENV_PATH="$ENV_FILE"
  exec su -s /bin/bash -c "exec \"${script_fullname}\"" intellectwebui || error_exit "su failed"
fi

new_gid=$(id -g)
new_uid=$(id -u)
[ "$WANTED_GID" = "$new_gid" ] && [ "$WANTED_UID" = "$new_uid" ] || error_exit "UID/GID mismatch"

tmp_root_env="${_HW_ROOT_ENV_PATH:-/tmp/intellectwebui_root_env.txt}"
[ -f "$tmp_root_env" ] && load_env "$tmp_root_env" true

if [ ! -x /app/bin/intellect-webui ] && [ -d /apptoo ]; then
  mkdir -p /app/bin /app/static
  cp -a /apptoo/. /app/ 2>/dev/null || true
fi

[ -d /app ] || error_exit "/app missing"
touch /app/.testfile && rm -f /app/.testfile || error_exit "/app not writable"

[ -n "${INTELLECT_WEBUI_STATE_DIR+x}" ] || error_exit "INTELLECT_WEBUI_STATE_DIR not set"
mkdir -p "$INTELLECT_WEBUI_STATE_DIR" || error_exit "cannot create state dir"
touch "$INTELLECT_WEBUI_STATE_DIR/.testfile" && rm -f "$INTELLECT_WEBUI_STATE_DIR/.testfile" || error_exit "state dir not writable"

export INTELLECT_WEBUI_DEFAULT_WORKSPACE="${INTELLECT_WEBUI_DEFAULT_WORKSPACE:-/workspace}"
mkdir -p "$INTELLECT_WEBUI_DEFAULT_WORKSPACE" 2>/dev/null || true

[ -x /app/bin/intellect-webui ] || error_exit "/app/bin/intellect-webui missing"
[ -d /app/static ] || error_exit "/app/static missing"

export INTELLECT_WEBUI_STATIC_DIR="${INTELLECT_WEBUI_STATIC_DIR:-/app/static}"
export PATH="/app/bin:${PATH}"

cd /app
exec /app/bin/intellect-webui
