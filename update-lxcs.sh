#!/usr/bin/env bash
set -Eeuo pipefail

# ====== SETTINGS ======
MAX_JOBS=10
REFRESH_SEC=1

# LOG_LEVEL:
#   2 = (default) high-level overview log (quiet on success; captures apt output on failures)
#   1 = debug (includes apt output for everything)
LOG_LEVEL="${LOG_LEVEL:-2}"

APT_UPGRADE_CMD='DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -y upgrade'
APT_CLEANUP_CMD='DEBIAN_FRONTEND=noninteractive apt-get -y autoremove && DEBIAN_FRONTEND=noninteractive apt-get -y autoclean'
# ======================

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RUN_TS="$(date '+%Y-%m-%d_%H%M%S')"
LOGFILE="${SCRIPT_DIR}/lxc-apt-upgrade_${RUN_TS}.log"
LOG_USE_COLOR="${LOG_USE_COLOR:-1}"

WORKDIR="$(mktemp -d)"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

mapfile -t CTS < <(pct list | awk 'NR>1 {print $1}')
if [[ ${#CTS[@]} -eq 0 ]]; then
  echo "no containers found via pct list"
  exit 0
fi

TOTAL="${#CTS[@]}"

c() {
  local code="$1"; shift
  if [[ "$LOG_USE_COLOR" == "1" ]]; then
    printf "\033[%sm%s\033[0m" "$code" "$*"
  else
    printf "%s" "$*"
  fi
}

CLR_GRAY="0;37"
CLR_CYAN="0;36"
CLR_GREEN="0;32"
CLR_RED="0;31"
CLR_YELLOW="0;33"
CLR_MAGENTA="0;35"
CLR_BOLD="1"

ts() { date -Is; }
job_count() { jobs -pr | wc -l | tr -d ' '; }

get_ct_name() {
  local ct="$1"
  local hn
  hn="$(pct config "$ct" 2>/dev/null | awk -F': ' '/^hostname:/{print $2; exit}')"
  [[ -n "${hn:-}" ]] && echo "$hn" || echo "CT$ct"
}

label_for() {
  local ct="$1"
  local name
  name="$(cat "${WORKDIR}/name.${ct}")"
  echo "${name} (CT ${ct})"
}

count_status() {
  local needle="$1"
  local c=0
  for ct in "${CTS[@]}"; do
    [[ "$(cat "${WORKDIR}/status.${ct}")" == "$needle" ]] && ((c++)) || true
  done
  echo "$c"
}

progress_bar() {
  local done="$1" total="$2" width=40
  local filled=$(( (done * width) / total ))
  local empty=$(( width - filled ))
  printf "[%*s%*s]" "$filled" "" "$empty" "" | tr ' ' '#'
}

log_hl() { echo "[$(ts)] $*" >> "$LOGFILE"; }

log_ui_snapshot() {
  local complete failed skipped running pending done_count
  complete="$(count_status COMPLETE)"
  failed="$(count_status FAILED)"
  skipped="$(count_status SKIPPED)"
  running="$(count_status RUNNING)"
  pending="$(count_status PENDING)"
  done_count=$((complete + failed + skipped))

  {
    echo "----------------------------------------------------------------"
    echo "UI SNAPSHOT @ $(ts)  host: $(hostname)"
    printf "overall: %s %d/%d  |  pending:%d  running:%d  complete:%d  failed:%d  skipped:%d\n" \
      "$(progress_bar "$done_count" "$TOTAL")" "$done_count" "$TOTAL" \
      "$pending" "$running" "$complete" "$failed" "$skipped"
    echo
    printf "%-28s %-10s %s\n" "CONTAINER" "STATUS" "INFO"
    printf "%-28s %-10s %s\n" "---------" "------" "----"
    for ct in "${CTS[@]}"; do
      local st msg label
      st="$(cat "${WORKDIR}/status.${ct}")"
      msg="$(cat "${WORKDIR}/msg.${ct}")"
      label="$(label_for "$ct")"
      printf "%-28s %-10s %s\n" "$label" "$st" "$msg"
    done
    echo "----------------------------------------------------------------"
  } >> "$LOGFILE"
}

render_ui() {
  local complete failed skipped running pending done_count
  complete="$(count_status COMPLETE)"
  failed="$(count_status FAILED)"
  skipped="$(count_status SKIPPED)"
  running="$(count_status RUNNING)"
  pending="$(count_status PENDING)"
  done_count=$((complete + failed + skipped))

  printf "\033[H\033[J"
  echo "lxc apt update/upgrade  |  host: $(hostname)  |  $(date '+%Y-%m-%d %H:%M:%S')"
  echo "log: $LOGFILE  |  LOG_LEVEL=$LOG_LEVEL"
  echo
  printf "overall: %s %d/%d  |  pending:%d  running:%d  complete:%d  failed:%d  skipped:%d\n" \
    "$(progress_bar "$done_count" "$TOTAL")" "$done_count" "$TOTAL" \
    "$pending" "$running" "$complete" "$failed" "$skipped"
  echo
  printf "%-28s %-10s %s\n" "CONTAINER" "STATUS" "INFO"
  printf "%-28s %-10s %s\n" "---------" "------" "----"

  for ct in "${CTS[@]}"; do
    local st msg label color
    st="$(cat "${WORKDIR}/status.${ct}")"
    msg="$(cat "${WORKDIR}/msg.${ct}")"
    label="$(label_for "$ct")"

    case "$st" in
      PENDING)  color="\033[0;37m" ;;
      RUNNING)  color="\033[0;36m" ;;
      COMPLETE) color="\033[0;32m" ;;
      FAILED)   color="\033[0;31m" ;;
      SKIPPED)  color="\033[0;33m" ;;
      *)        color="\033[0m" ;;
    esac

    printf "%-28s ${color}%-10s\033[0m %s\n" "$label" "$st" "$msg"
  done
}

log_header() {
  {
    echo "============================================================"
    echo "LXC apt update/upgrade run: $(ts)"
    echo "Host: $(hostname)"
    echo "MAX_JOBS=${MAX_JOBS}"
    echo "REFRESH_SEC=${REFRESH_SEC}"
    echo "LOG_LEVEL=${LOG_LEVEL}"
    echo "Total containers discovered: ${TOTAL}"
    echo "Containers:"
    for ct in "${CTS[@]}"; do
      echo "  - $(label_for "$ct")"
    done
    echo "============================================================"
  } >> "$LOGFILE"
}

log_footer_summary() {
  local complete failed skipped pending running
  complete="$(count_status COMPLETE)"
  failed="$(count_status FAILED)"
  skipped="$(count_status SKIPPED)"
  pending="$(count_status PENDING)"
  running="$(count_status RUNNING)"

  {
    echo "------------------------------------------------------------"
    echo "END: $(ts)"
    echo "SUMMARY:"
    echo "  total:     ${TOTAL}"
    echo "  complete:  ${complete}"
    echo "  failed:    ${failed}"
    echo "  skipped:   ${skipped}"
    echo "  running:   ${running}"
    echo "  pending:   ${pending}"
    echo "------------------------------------------------------------"
  } >> "$LOGFILE"
}

for ct in "${CTS[@]}"; do
  echo "PENDING" > "${WORKDIR}/status.${ct}"
  echo ""        > "${WORKDIR}/msg.${ct}"
  echo "$(get_ct_name "$ct")" > "${WORKDIR}/name.${ct}"
  echo "0" > "${WORKDIR}/reboot.${ct}"
done

do_upgrade_ct() {
  local ct="$1"
  local label status
  label="$(label_for "$ct")"
  status="$(pct status "$ct" | awk '{print $2}')"

  if [[ "$status" != "running" ]]; then
    echo "SKIPPED" > "${WORKDIR}/status.${ct}"
    echo "stopped" > "${WORKDIR}/msg.${ct}"
    log_hl "$(c "$CLR_YELLOW" "SKIPPED")  ${label} (not running)"
    return 0
  fi

  echo "RUNNING" > "${WORKDIR}/status.${ct}"
  echo "apt update/upgrade" > "${WORKDIR}/msg.${ct}"
  log_hl "$(c "$CLR_CYAN" "START")    ${label} upgrade"

  if [[ "$LOG_LEVEL" == "1" ]]; then
    if ! pct exec "$ct" -- bash -lc "$APT_UPGRADE_CMD" 2>&1 | sed -u "s/^/[${label}] /" >> "$LOGFILE"; then
      local rc=$?
      echo "FAILED" > "${WORKDIR}/status.${ct}"
      echo "exit=${rc} (see logfile)" > "${WORKDIR}/msg.${ct}"
      log_hl "$(c "$CLR_RED" "FAILED")   ${label} rc=${rc}"
      return "$rc"
    fi
  else
    if ! pct exec "$ct" -- bash -lc "$APT_UPGRADE_CMD" >> /dev/null 2>&1; then
      local rc=$?
      echo "FAILED" > "${WORKDIR}/status.${ct}"
      echo "exit=${rc} (apt output captured)" > "${WORKDIR}/msg.${ct}"
      log_hl "$(c "$CLR_RED" "FAILED")   ${label} rc=${rc} (capturing apt output)"

      {
        echo "----- BEGIN APT OUTPUT (failure) : ${label} rc=${rc} -----"
      } >> "$LOGFILE"

      pct exec "$ct" -- bash -lc "$APT_UPGRADE_CMD" 2>&1 | sed -u "s/^/[${label}] /" >> "$LOGFILE" || true

      {
        echo "----- END APT OUTPUT (failure) : ${label} -----"
      } >> "$LOGFILE"

      return "$rc"
    fi
  fi

  echo "COMPLETE" > "${WORKDIR}/status.${ct}"

  if pct exec "$ct" -- test -f /var/run/reboot-required >/dev/null 2>&1; then
    echo "1" > "${WORKDIR}/reboot.${ct}"
    echo "done (reboot required)" > "${WORKDIR}/msg.${ct}"
    log_hl "$(c "$CLR_GREEN" "DONE")     ${label} $(c "$CLR_MAGENTA" "(reboot required)")"
  else
    echo "done" > "${WORKDIR}/msg.${ct}"
    log_hl "$(c "$CLR_GREEN" "DONE")     ${label}"
  fi
}

do_cleanup_ct() {
  local ct="$1"
  local label status
  label="$(label_for "$ct")"

  [[ "$(cat "${WORKDIR}/status.${ct}")" == "COMPLETE" ]] || return 0

  status="$(pct status "$ct" | awk '{print $2}')"
  if [[ "$status" != "running" ]]; then
    log_hl "$(c "$CLR_YELLOW" "SKIP")     ${label} cleanup (not running)"
    return 0
  fi

  log_hl "$(c "$CLR_CYAN" "START")    ${label} cleanup"

  if [[ "$LOG_LEVEL" == "1" ]]; then
    if pct exec "$ct" -- bash -lc "$APT_CLEANUP_CMD" 2>&1 | sed -u "s/^/[${label}][cleanup] /" >> "$LOGFILE"; then
      log_hl "$(c "$CLR_GREEN" "DONE")     ${label} cleanup"
    else
      local rc=$?
      log_hl "$(c "$CLR_RED" "FAILED")   ${label} cleanup rc=${rc}"
      return "$rc"
    fi
  else
    if ! pct exec "$ct" -- bash -lc "$APT_CLEANUP_CMD" >> /dev/null 2>&1; then
      local rc=$?
      log_hl "$(c "$CLR_RED" "FAILED")   ${label} cleanup rc=${rc} (capturing output)"

      {
        echo "----- BEGIN CLEANUP OUTPUT (failure) : ${label} rc=${rc} -----"
      } >> "$LOGFILE"

      pct exec "$ct" -- bash -lc "$APT_CLEANUP_CMD" 2>&1 | sed -u "s/^/[${label}][cleanup] /" >> "$LOGFILE" || true

      {
        echo "----- END CLEANUP OUTPUT (failure) : ${label} -----"
      } >> "$LOGFILE"

      return "$rc"
    fi

    log_hl "$(c "$CLR_GREEN" "DONE")     ${label} cleanup"
  fi
}

do_reboot_ct() {
  local ct="$1"
  local label status
  label="$(label_for "$ct")"

  [[ "$(cat "${WORKDIR}/reboot.${ct}")" == "1" ]] || return 0

  status="$(pct status "$ct" | awk '{print $2}')"
  if [[ "$status" != "running" ]]; then
    log_hl "$(c "$CLR_YELLOW" "SKIP")     ${label} reboot (not running)"
    return 0
  fi

  log_hl "$(c "$CLR_CYAN" "REBOOT")   ${label}"
  if pct reboot "$ct" >> "$LOGFILE" 2>&1; then
    log_hl "$(c "$CLR_GREEN" "DONE")     ${label} reboot issued"
  else
    local rc=$?
    log_hl "$(c "$CLR_RED" "FAILED")   ${label} reboot rc=${rc}"
    return "$rc"
  fi
}

log_header
log_hl "$(c "$CLR_BOLD" "MODE")     LOG_LEVEL=${LOG_LEVEL}"
log_hl "$(c "$CLR_BOLD" "LOGFILE")  ${LOGFILE}"

(
  while true; do
    render_ui
    sleep "$REFRESH_SEC"
    complete="$(count_status COMPLETE)"
    failed="$(count_status FAILED)"
    skipped="$(count_status SKIPPED)"
    done_count=$((complete + failed + skipped))
    [[ "$done_count" -ge "$TOTAL" ]] && break
  done
  render_ui
) &
UI_PID=$!

for ct in "${CTS[@]}"; do
  while [[ "$(job_count)" -ge "$MAX_JOBS" ]]; do sleep 0.1; done
  do_upgrade_ct "$ct" &
done

wait || true
wait "$UI_PID" 2>/dev/null || true

log_footer_summary
log_ui_snapshot

REBOOT_LIST=()
CLEAN_LIST=()
for ct in "${CTS[@]}"; do
  [[ "$(cat "${WORKDIR}/reboot.${ct}")" == "1" ]] && REBOOT_LIST+=("$ct")
  [[ "$(cat "${WORKDIR}/status.${ct}")" == "COMPLETE" ]] && CLEAN_LIST+=("$ct")
done

echo
echo "summary: total=$TOTAL complete=$(count_status COMPLETE) failed=$(count_status FAILED) skipped=$(count_status SKIPPED)"
echo "logfile: $LOGFILE"
echo

if [[ ${#CLEAN_LIST[@]} -gt 0 ]]; then
  echo "cleanup candidates:"
  for ct in "${CLEAN_LIST[@]}"; do echo "  - $(label_for "$ct")"; done
  read -r -p "run cleanup on these containers? [y/N]: " ans
  if [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]; then
    log_hl "$(c "$CLR_BOLD" "CLEANUP") start"
    for ct in "${CLEAN_LIST[@]}"; do do_cleanup_ct "$ct" || true; done
    log_hl "$(c "$CLR_BOLD" "CLEANUP") end"
    echo "cleanup done."
  else
    log_hl "$(c "$CLR_BOLD" "CLEANUP") skipped by user"
    echo "cleanup skipped."
  fi
else
  echo "no cleanup candidates."
fi

echo

if [[ ${#REBOOT_LIST[@]} -gt 0 ]]; then
  echo "reboot required:"
  for ct in "${REBOOT_LIST[@]}"; do echo "  - $(label_for "$ct")"; done
  read -r -p "reboot these containers now? [y/N]: " ans
  if [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]; then
    log_hl "$(c "$CLR_BOLD" "REBOOT") start"
    for ct in "${REBOOT_LIST[@]}"; do do_reboot_ct "$ct" || true; done
    log_hl "$(c "$CLR_BOLD" "REBOOT") end"
    echo "reboots issued."
  else
    log_hl "$(c "$CLR_BOLD" "REBOOT") skipped by user"
    echo "reboots skipped."
  fi
else
  echo "no containers reported reboot-required."
fi

echo
log_hl "$(c "$CLR_BOLD" "DONE") run complete"
echo "done. logfile: $LOGFILE"
echo
echo "view log with: less -R $LOGFILE"
