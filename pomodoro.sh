#!/bin/zsh

set -euo pipefail

# pomodoro.sh
# to track your pomodoro session from the shell, and play a sound, show
# notification after pomodoro finished
# In that case send a `USR1` signal to the process if you want to see the
# elapsed time
#
# The script will update you slack status if slack token set
# You can set slack token by setting the `SLACK_TOKEN` env var
# Or put the token into a gpg encrypted file to `$HOME/.secret/slack_token.gpg`
# You can override that path by setting the `SLACK_TOKEN_FILE_PATH` env var

DEFAULT_MINUTES=25
NOTIFY_SEND="/usr/bin/notify-send"
DUNSTIFY="$HOME/bin/dunstify"
DEFAULT_SOUND="/usr/share/sounds/purple/alert.wav"
DEFAULT_DESCRIPTION="Pomodoro"
DEFAULT_LOGFILE="$HOME/.pomodoro.log"

MINUTES=${POMODORO_MINUTES:-$DEFAULT_MINUTES}
SOUND=${POMODORO_SOUND:-$DEFAULT_SOUND}
DESCRIPTION=${POMODORO_DESCRIPTION:-$DEFAULT_DESCRIPTION}
LOGFILE=${POMODORO_LOG_FILE:-$DEFAULT_LOGFILE}
TAGS=""

DEFAULT_SLACK_TOKE_FILE_PATH="$HOME/.secret/slack_token.gpg"
SLACK_TOKEN_FILE_PATH=${POMODORO_SLACK_TOKEN_FILE_PATH:-$DEFAULT_SLACK_TOKE_FILE_PATH}
DEFAULT_SLACK_EMOJI=":tomato:"
DEFAULT_SLACK_STATUS_TEXT=""
SLACK_EMOJI=${POMODORO_SLACK_EMOJI:-$DEFAULT_SLACK_EMOJI}
SLACK_STATUS_TEXT=${POMODORO_SLACK_STATUS_TEXT:-$DEFAULT_SLACK_STATUS_TEXT}

PID_FILE="/tmp/pomodoro"

INITIAL_SLACK_STATUS_EMOJI=""
INITIAL_SLACK_STATUS_TEXT=""

SLACK_TOKEN=""
NO=""
QUIET=0
DURATION=0

start=$(date -u +%s)

help() {
	echo "pomodoro.sh"
	echo
	echo "Options:"
	echo "  -m minutes Duration of the pomodoro session in minutes ($DEFAULT_MINUTES is the default)"
	echo "  -a alarm_sound_file played after pomodoro finished ($DEFAULT_SOUND is the default)"
	echo "  -d \"Pomodoro session description\" (\"$DEFAULT_DESCRIPTION\" is the default)"
	echo "  -l /path/to/logfile ($DEFAULT_LOGFILE is the default)"
	echo "  -t list,of,tags stored in the log file"
	echo "  -q Don't show elapsed time"
	echo "  -n feature Turn off feature."
	echo "     Available values:"
	echo "       SLACK"
	echo "  -h Show this help"
	echo
	echo "Signals:"
	echo "  Send an USR1 to print elapsed time (useful if -q is used)"
	echo
	echo "Some of the parameters can be configured with environment variables:"
	echo "  POMODORO_MINUTES Same as -m option. Duration of the pomodoro session in minutes"
	echo "  POMODORO_SOUND Same as -a option. Sound file played after pomodoro finished"
	echo "  POMODORO_DESCRIPTION Same as -d option. Description for the session"
	echo "  POMODORO_LOG_FILE Same as -l option. Log file path"
	echo "  POMODORO_SLACK_TOKEN_FILE_PATH Path to a gpg encrypted file which content is your slack token"
	echo "  POMODORO_SLACK_EMOJI An emoji as text which should be shown when you are doing in a pomodoro session"
	echo "  POMODORO_SLACK_STATUS_TEXT Status message shown during pomodoro session"
	echo
	echo "Dependencies:"
	echo "  gpg if you store your slack token in gpg encrypted file"
	echo "  curl to call slack api"
	echo "  jq for slack related functions: https://stedolan.github.io/jq/"
	echo "  aplay to play sound after pomodoro finished"
	echo "  date to show elapsed time"
	echo
	echo "Usage $0 [-m minutes] [-a sound_file.wav] [-q]"
}

get_time_string() {
	local dt=$1
	local ds="$((dt % 60))"
	local dm="$(( (dt / 60) % 60))"
	local dh="$((dt / 3600))"
	printf '%d:%02d:%02d' $dh $dm $ds
}

show_elapsed_time() {
	local elapsed=$(($(date -u +%s) - start))
	local dt=$((DURATION - elapsed))
	local remaining
	remaining=$(get_time_string "$dt")

	printf "\r%s" "$remaining"
	printf "%s" "$remaining" > $PID_FILE
}

slack_call() {
	if [ -z "$SLACK_TOKEN" ];then
		return 0
	fi

	local api="$1"
	local data="$2"

	local url="https://slack.com/api/$api"

	if [ -z "$data" ];then
		curl -s -H 'Content-Type: application/json; charset=utf-8' -H "Authorization: Bearer $SLACK_TOKEN" "$url"
	else
		curl -s -H 'Content-Type: application/json; charset=utf-8' -H "Authorization: Bearer $SLACK_TOKEN" -d "$data" "$url"
	fi
}

set_slack_status() {
	local emoji
	emoji="$1"
	local status_text
	status_text="$2"

	local data
	data=$(jq -c -n --arg emoji "$emoji" --arg status_text "$status_text" '{"profile": {"status_emoji": $emoji, "status_text": $status_text}}')

	slack_call 'users.profile.set' "$data" "" > /dev/null
}

set_default_slack_status() {
	set_slack_status "$INITIAL_SLACK_STATUS_EMOJI" "$INITIAL_SLACK_STATUS_TEXT"
}

set_slack_snooze() {
	local minutes

	minutes="$1"
	slack_call "dnd.setSnooze?num_minutes=$minutes" "" > /dev/null
}

get_slack_status() {
	local current_status
	current_status="$(slack_call 'users.profile.get' '')"

	INITIAL_SLACK_STATUS_TEXT=$(echo "$current_status" | jq -r '.profile.status_text')
	INITIAL_SLACK_STATUS_EMOJI=$(echo "$current_status" | jq -r '.profile.status_emoji')
}

log_pomodoro_done() {
	local when
	local duration
	when=$(date -Iseconds)
	duration=$((($(date -u +%s) - start) / 60))

	printf "%s\t%i\t%s\t%s\n" "$when" $duration "$TAGS" "$DESCRIPTION" >> "$LOGFILE"
}

stop_pomodoro() {
	echo "stopping $DESCRIPTION"
	aplay -q "$SOUND"

	echo
	date
	local msg
	msg="Pomodoro finished, take a break!"
	echo $msg
	log_pomodoro_done

	if [ -e "$DUNSTIFY" ];then
		$DUNSTIFY -p -a "$0" -u normal "$msg"
	else
		$NOTIFY_SEND -p -a "$0" -u normal "$msg"
	fi
	set_slack_snooze 0
	set_default_slack_status

	rm $PID_FILE
	exit 0
}

start_pomodoro() {
	echo "Pomodoro will run $MINUTES minutes. PID: $$"

	get_slack_status
	set_slack_snooze "$MINUTES"
	set_slack_status "$SLACK_EMOJI" "$SLACK_STATUS_TEXT"

	while [ $(($(date -u +%s) - start)) -lt $DURATION ];do
		sleep 1

		if [ $QUIET -eq 0 ];then
			show_elapsed_time
		fi
	done
}

while getopts "m:a:n:d:l:t:qh" opt;do
	case $opt in
		'm')
			MINUTES=$OPTARG
			;;

		'a')
			SOUND=$OPTARG
			;;

		'd')
			DESCRIPTION=$OPTARG
			;;

		'l')
			LOGFILE=$OPTARG
			;;

		't')
			TAGS=$OPTARG
			;;

		'q')
			QUIET=1
			;;

		'n')
			NO="$NO $OPTARG"
			;;

		'h')
			help
			exit 0
			;;

		[?])
			help
			exit 1
			;;
	esac
done

NO=$(echo "$NO" | tr '[:lower:]' '[:upper:]')

NO_SLACK=0

for noopt in $NO;do
	case $noopt in
		'SLACK')
			NO_SLACK=1
			;;
	esac
done

if [ -z "$SLACK_TOKEN" ] && [ -f "$SLACK_TOKEN_FILE_PATH" ] && [ $NO_SLACK -eq 0 ];then
	SLACK_TOKEN=$(gpg -d "$SLACK_TOKEN_FILE_PATH" 2>/dev/null)
fi

DURATION=$((60 * MINUTES))

trap 'show_elapsed_time' USR1
trap 'stop_pomodoro' 2

start_pomodoro
stop_pomodoro

exit 0
