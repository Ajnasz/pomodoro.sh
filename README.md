# pomodoro.sh

pomodoro.sh to track your pomodoro session and play a sound, shownotification
after pomodoro finished
In that case send a `USR1` signal to the process if you want to see the elapsed time

The script will update you slack status if slack token set
You can set slack token by setting the `SLACK_TOKEN` env var
Or put the token into a gpg encrypted file to `$HOME/.secret/slack_token.gpg`
You can override that path by setting the `SLACK_TOKEN_FILE_PATH` env var

## Options

-  -m minutes Duration of the pomodoro session in minutes (see `$DEFAULT_MINUTES` in the source for default value)
-  -a alarm_sound_file played after pomodoro finished (see `$DEFAULT_SOUND` in the source for default value)
-  -q Don't show elapsed time
-  -n feature Turn off feature. Available values:
  * SLACK
-  -h Show help

## Signals

Send an `USR1` to print elapsed time (useful if -q is used)

## Environment variables

Some of the parameters can be configured with environment variables:

-  `POMODORO_MINUTES` Same as -m option. Duration of the pomodoro session in minutes
-  `POMODORO_SOUND` Same as -a option. Sound file played after pomodoro finished
-  `POMODORO_SLACK_TOKEN_FILE_PATH` Path to a gpg encrypted file which content is your slack token
-  `POMODORO_SLACK_EMOJI` An emoji as text which should be shown when you are doing in a pomodoro session
-  `POMODORO_SLACK_STATUS_TEXT` Status message shown during pomodoro session

## Dependencies

-  _aplay_ to play sound after pomodoro finished
-  _date_ for time related functions
-  _gpg_ if you store your slack token in gpg encrypted file
-  _curl_ to call slack api
-  _jq_ for slack related functions: [https://stedolan.github.io/jq/](https://stedolan.github.io/jq/)
