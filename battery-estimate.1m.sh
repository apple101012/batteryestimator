#!/bin/zsh

set -u

format_minutes_as_clock() {
  local minutes="$1"

  if [[ -z "$minutes" || ! "$minutes" =~ '^[0-9]+$' || "$minutes" == "65535" ]]; then
    return 1
  fi

  local hours=$(( minutes / 60 ))
  local mins=$(( minutes % 60 ))
  printf '%d:%02d\n' "$hours" "$mins"
}

read_avg_time_to_full() {
  ioreg -r -n AppleSmartBattery 2>/dev/null | awk '/"AvgTimeToFull" = / { print $3; exit }'
}

human_process_name() {
  local raw="$1"
  local name="${raw:t}"
  local app_name=""

  if [[ "$raw" == *".app/"* ]]; then
    app_name="${${raw%%.app*}:t}"
  fi

  case "$name" in
    "Electron Helper"|"Electron Helper (Renderer)"|"Codex Helper"|"Codex Helper (Renderer)"|"Discord Helper (Renderer)"|"plugin-container")
      if [[ -n "$app_name" && "$app_name" != "$name" ]]; then
        name="$app_name ($name)"
      fi
      ;;
    *)
      if [[ -n "$app_name" && "${name:l}" == "${app_name:l}" ]]; then
        name="$app_name"
      fi
      ;;
  esac

  printf '%s\n' "$name"
}

top_energy_users() {
  ps -A -r -o pid=,pcpu=,pmem=,comm= 2>/dev/null | awk '
    {
      pid = $1
      cpu = $2
      mem = $3
      command = $4
      for (i = 5; i <= NF; i++) {
        command = command " " $i
      }

      if (command ~ /\/(ps|awk|sed|sort|head|tail|zsh)$/ || command ~ /battery-estimate(\.1m)?\.sh$/) {
        next
      }

      print pid "\t" cpu "\t" mem "\t" command
    }
  ' | head -n 5
}

info="$(pmset -g batt 2>/dev/null)"
source_line="$(printf '%s\n' "$info" | sed -n '1p')"
battery_line="$(printf '%s\n' "$info" | sed -n '2p')"

percent="$(printf '%s\n' "$battery_line" | awk -F'\t' '{print $2}' | awk -F'; ' '{print $1}')"
charge_state="$(printf '%s\n' "$battery_line" | awk -F'; ' '{print $2}')"
raw_eta="$(printf '%s\n' "$battery_line" | awk -F'; ' '{print $3}')"
eta="${raw_eta% present:*}"
eta="${eta% remaining*}"
source_text="${source_line#Now drawing from }"
source_text="${source_text%\'}"
source_text="${source_text#\'}"
has_eta=1
if [[ -z "${eta}" || "${eta}" == *"no estimate"* ]]; then
  has_eta=0
fi

if [[ "${charge_state}" == "charging" ]] && (( ! has_eta )); then
  avg_time_to_full_minutes="$(read_avg_time_to_full)"
  avg_time_to_full="$(format_minutes_as_clock "${avg_time_to_full_minutes:-}")"
  if [[ -n "${avg_time_to_full}" ]]; then
    eta="${avg_time_to_full}"
    has_eta=1
  fi
fi

if [[ -z "${percent}" ]]; then
  echo "Battery --"
  echo "---"
  echo "Unable to read battery state from pmset."
  exit 0
fi

title="$percent"
case "${charge_state}" in
  discharging)
    if (( has_eta )); then
      title="$percent ${eta}"
    else
      title="$percent --"
    fi
    ;;
  charging)
    if (( has_eta )); then
      title="$percent +${eta}"
    else
      title="$percent charging"
    fi
    ;;
  charged)
    title="$percent full"
    ;;
  *)
    if [[ -n "${charge_state}" ]]; then
      title="$percent ${charge_state}"
    fi
    ;;
esac

echo "$title"
echo "---"
echo "Battery: $percent"
echo "Status: ${charge_state:-unknown}"
if (( has_eta )); then
  if [[ "${charge_state}" == "charging" ]]; then
    echo "Time to full: $eta"
  else
    echo "Estimate remaining: $eta"
  fi
fi
if [[ -n "${source_text}" ]]; then
  echo "Source: $source_text"
fi
echo "---"
echo "Top Energy Users (Approx)"

energy_lines="$(top_energy_users)"
if [[ -z "${energy_lines}" ]]; then
  echo "No process data available right now."
else
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    pid="$(printf '%s\n' "$line" | awk -F'\t' '{print $1}')"
    cpu="$(printf '%s\n' "$line" | awk -F'\t' '{print $2}')"
    mem="$(printf '%s\n' "$line" | awk -F'\t' '{print $3}')"
    raw_command="$(printf '%s\n' "$line" | awk -F'\t' '{print $4}')"
    display_name="$(human_process_name "$raw_command")"
    echo "${display_name}: ${cpu}% CPU, ${mem}% RAM | bash='open' param1='-a' param2='Activity Monitor' terminal=false"
    echo "-- PID ${pid}"
  done <<< "$energy_lines"
fi
echo "---"
echo "Open Activity Monitor | bash='open' param1='-a' param2='Activity Monitor' terminal=false"
echo "Refresh now | refresh=true"
