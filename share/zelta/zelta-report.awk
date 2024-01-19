#!/usr/bin/awk -f

function env(env_name, var_default) {
	return ( (env_name in ENVIRON) ? ENVIRON[env_name] : var_default )
}

function err(msg) {
	print msg
	exit 1
}

BEGIN {
	ZELTA_CONFIG = env("ZELTA_CONFIG", "/usr/local/etc/zelta/zelta.conf")
	"awk '/^BACKUP_ROOT: /{print $2}' " ZELTA_CONFIG | getline BACKUP_ROOT
	HOOK_FILE = env("SLACK_HOOK", ENVIRON["HOME"] "/.zeport-hook")
	getline SLACK_HOOK < HOOK_FILE
	if (! SLACK_HOOK || ! BACKUP_ROOT) err("please correctly set BACKUP_ROOT and SLACK_HOOK")
	"hostname" | getline HOSTNAME
	too_old = systime() - 86400
	trim = length(BACKUP_ROOT) + 1
	FS = "[@\t]+"
	# This seems to be faster than trying to limit the list in any way:
	while ("zfs list -Hprt snap -oname,creation -S creation "BACKUP_ROOT | getline) {
		if (snaplist[$1]) continue
		snaplist[$1]++
		sub(BACKUP_ROOT"/", "")
		if ($3 < too_old) {
			old_list[$1]++
		}
	}

	SLACK_MESSAGE = HOSTNAME ":" BACKUP_ROOT " "
	if (length(old_list) > 0) {
		SLACK_MESSAGE = "\*" SLACK_MESSAGE "snapshots are out of date:\* "
		for (s in old_list) { SLACK_MESSAGE = SLACK_MESSAGE s" " }
	} else { SLACK_MESSAGE = "\*" SLACK_MESSAGE "snapshots are up to date.\*" }

	curl = 	"curl -s -X POST -H 'Content-type: application/json; charset=utf-8' " \
	     	"--data '{ \"username\": \"zeport\", \"icon_emoji\": \":camera_with_flash:\", \"text\": \"" \
		SLACK_MESSAGE "\" }' " SLACK_HOOK

	curl | getline
}
