#!/bin/sh
# Waybar custom battery module. Emits a JSON object when a battery is
# present; emits NOTHING on machines without one (desktops), so the module
# renders empty and takes no space -- the graceful-hide the base config
# relies on. Referenced from ~/.config/waybar/config as custom/battery.

# Find the first real battery (BAT0/BAT1/...). Skip AC adapters.
bat=""
for d in /sys/class/power_supply/BAT*; do
	test -e "$d/capacity" || continue
	bat="$d"
	break
done
test -n "$bat" || exit 0 # no battery: print nothing, module stays hidden

cap=$(cat "$bat/capacity" 2>/dev/null)
status=$(cat "$bat/status" 2>/dev/null)
test -n "$cap" || exit 0

# class drives the CSS colour (see style.css).
class="normal"
if test "$status" = "Charging"; then
	class="charging"
elif test "$cap" -le 15; then
	class="critical"
elif test "$cap" -le 30; then
	class="warning"
fi

case "$status" in
Charging) label="chg ${cap}%" ;;
Full) label="full" ;;
*) label="bat ${cap}%" ;;
esac

printf '{"text":"%s","tooltip":"Battery %s%% (%s)","class":"%s","percentage":%s}\n' \
	"$label" "$cap" "$status" "$class" "$cap"
