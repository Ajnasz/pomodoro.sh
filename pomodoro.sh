#!/bin/sh

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
MINUTES=${POMODORO_MINUTES:-$DEFAULT_MINUTES}
SOUND=${POMODORO_SOUND:-$DEFAULT_SOUND}
DEFAULT_SLACK_TOKE_FILE_PATH="$HOME/.secret/slack_token.gpg"
SLACK_TOKEN_FILE_PATH=${POMODORO_SLACK_TOKEN_FILE_PATH:-$DEFAULT_SLACK_TOKE_FILE_PATH}
DEFAULT_SLACK_EMOJI=":tomato:"
DEFAULT_SLACK_STATUS_TEXT=""
SLACK_EMOJI=${POMODORO_SLACK_EMOJI:-$DEFAULT_SLACK_EMOJI}
SLACK_STATUS_TEXT=${POMODORO_SLACK_STATUS_TEXT:-$DEFAULT_SLACK_STATUS_TEXT}

DEFAULT_SLACK_STATUS_EMOJI=""
DEFAULT_SLACK_STATUS_TEXT=""

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
	dt=$1
	local ds=$((dt % 60))
	local dm=$(((dt / 60) % 60))
	local dh=$((dt / 3600))
	printf '%d:%02d:%02d' $dh $dm $ds
}

show_elapsed_time() {
	local elapsed=$(($(date -u +%s) - $start))
	dt=$(($DURATION - $elapsed))
	remaining=$(get_time_string "$dt")

	echo -n "\r$remaining"
}

slack_call() {
	if [ -z "$SLACK_TOKEN" ];then
		return 0
	fi
	local api=$1
	local data=$2
	local url="https://slack.com/api/$api"

	if [ -z "$data" ];then
		curl -s -H 'Content-Type: application/json; charset=utf-8' -H "Authorization: Bearer $SLACK_TOKEN" $url
	else
		curl -s -H 'Content-Type: application/json; charset=utf-8' -H "Authorization: Bearer $SLACK_TOKEN" -d "$data" $url
	fi
}

set_slack_status() {
	local emoji=$1
	local status_text=$2
	if [ -z "$emoji" ];then
		data='{"profile": {"status_text": "'$DEFAULT_SLACK_STATUS_TEXT'", "status_emoji": "'$DEFAULT_SLACK_STATUS_EMOJI'"}}'
	else
		data='{"profile": {"status_emoji": "'$emoji'", "status_text": "'$status_text'"}}'
	fi

	slack_call 'users.profile.set' "$data" > /dev/null
}

set_slack_snooze() {
	local minutes=$1
	slack_call "dnd.setSnooze?num_minutes=$minutes" > /dev/null
}

get_slack_status() {
	local STATUS="$(slack_call 'users.profile.get' | jq -r '.profile.status_emoji, .profile.status_text')"
	DEFAULT_SLACK_STATUS_TEXT=$(echo $STATUS | cut -d ' ' -f 2)
	DEFAULT_SLACK_STATUS_EMOJI=$(echo $STATUS | cut -d ' ' -f 1)
}

stop_pomodoro() {
	echo "stopping"
	aplay -q $SOUND

	echo
	date
	MSG="Pomodoro finished, take a break!"
	echo $MSG

	if [ -e "$DUNSTIFY" ];then
		$DUNSTIFY -p -a "$0" -u normal "$MSG"
	else
		$NOTIFY_SEND -p -a "$0" -u normal "$MSG"
	fi
	set_slack_snooze 0
	set_slack_status ''

	exit 0
}

while getopts "m:a:n:qh" opt;do
	case $opt in
		'm')
			MINUTES=$OPTARG
			;;

		'a')
			SOUND=$OPTARG
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

NO=$(echo $NO | tr '[:lower:]' '[:upper:]')

NO_SLACK=0

echo $NO
for noopt in $NO;do
	case $noopt in
		'SLACK')
			NO_SLACK=1
			;;
	esac
done



if [ -z "$SLACK_TOKEN" ] && [ -f "$SLACK_TOKEN_FILE_PATH" ] && [ $NO_SLACK -eq 0 ];then
	SLACK_TOKEN=$(gpg -d $HOME/.secret/slack_token.gpg 2>/dev/null)
fi

echo "Pomodoro will run $MINUTES minutes. PID: $$"

get_slack_status
set_slack_snooze $MINUTES
set_slack_status "$SLACK_EMOJI" "$SLACK_STATUS_TEXT"

DURATION=$((60 * MINUTES))

trap 'show_elapsed_time' USR1
trap 'stop_pomodoro' 2

while [ $(($(date -u +%s) - $start)) -lt $DURATION ];do
	sleep 1

	if [ $QUIET -eq 0 ];then
		show_elapsed_time
	fi
done

stop_pomodoro

exit 0
