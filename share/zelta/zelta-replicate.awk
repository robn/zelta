#!/usr/bin/awk -f
#
# zelta replicate (zpull) - replicates a snapshot and its descendants
#
# usage: zpull [user@][host:]source/dataset [user@][host:]target/dataset
#
# After using zmatch to identify out-of-date snapshots on the target, zpull creates
# individual replication streams for a snapshot and its children. zpull is useful for
# migrations in that it will recursively replicate the latest parent snapshot and its
# children, unlike the "zfs send -R" option.
#
# If called with the environmental variable ZELTA_PIPE=1, zpull reports an abbreviated
# output for reporting:
#
# 	received_streams, total_bytes, time, error
#
# Additional flags can be set with the environmental variables ZPULL_SEND_FLAGS,
# ZPULL_RECV_FLAGS, and ZPULL_I_FLAGS (for incremental streams only).
#
# Note that as zpull is used as a backup and migration tool, the default behavior for new
# replicas is to only copy the latest snapshots from the source heirarchy, while the
# behavior for updating existing replicas is to copy intermediate snapshots. You can use
# "ZPULL_SEND_FLAGS=R" to bootstrap a new backup repository to keep backup history. Use
# "ZPULL_I_FLAGS=i" to only copy the latest snapshot.


function error(string) { print "error: "string | "cat 1>&2" }

function verbose(message) { if (c["VERBOSE"]) print message }

function usage(message) {
	if (message) error(message)
	verbose("usage: zelta pull [-j] [user@][host:]source/dataset [user@][host:]target/dataset")
	exit 1
}

function env(env_name, var_default) {
	return ( (env_name in ENVIRON) ? ENVIRON[env_name] : var_default )
}

function q(s) { return "\'"s"\'" }

function opt_var() {
	var = ($0 ? $0 : ARGV[++i])
	$0 = ""
	return var
}

function get_options() {
	for (i=1;i<ARGC;i++) {
		$0 = ARGV[i]
		if (gsub(/^-/,"")) {
			if (gsub(/d/,"")) c["DEPTH"] = opt_var()
			if (gsub(/n/,"")) c["DRY_RUN"]++
			if (gsub(/j/,"")) c["JSON"]++
			if (gsub(/R/,"")) c["REPLICATE_NEW"]++
			if (/./) usage("unkown options: " $0)
		} else if (target) {
			usage("too many options: " $0)
		} else if (source) target = $0
		else source = $0
	}
	if (! target) usage()
	c["VERBOSE"] = (!c["JSON"] && !ZELTA_PIPE)
}
	       
function load_config() {
	ZELTA_CONFIG = env("ZELTA_CONFIG", "/usr/local/etc/zelta/zelta.conf")
	FS = "[: \t]+";
	while ((getline < ZELTA_CONFIG)>0) {
		if (split($0, arr, "#")) {
			$0 = arr[1]
		}
		gsub(/[ \t]+$/, "", $0)
		if (/^[^ ]+: +[^ ]/) {
			c[$1] = $2
		}
	}
	ZELTA_PIPE = env("ZELTA_PIPE", 0)
	get_options()
	send_flags = "Lcp"
	send_flags = send_flags (c["DRY_RUN"]?"n":"") (c["REPLICATE_NEW"]?"R":"")
	send_flags = c["REPLICATE_NEW"] ? "LcpR" : "Lcp"
	send_flags = "send -P" send_flags " " 
	recv_flags = c["RECEIVE_FLAGS"] ? c["RECEIVE_FLAGS"] : "u"
	recv_flags = "receive -v" env("ZPULL_RECV_FLAGS", recv_flags) " "
	intr_flags = c["INTERMEDIATE"] ? "I" : "i"
	intr_flags = "-" env("ZPULL_I_FLAGS", intr_flags) " "
	zmatch = "ZELTA_PIPE=1 /usr/bin/time zmatch " q(source) " " q(target) " 2>&1"
	if (c["DEPTH"] && !c["REPLICATE_NEW"]) {
		zmatch = "ZELTA_DEPTH=" c["DEPTH"] " " zmatch
	}
}

function get_endpoint_info(endpoint) {
	if (split(endpoint, vol_arr, ":") == 2) {
		ssh_command[endpoint] = "ssh " vol_arr[1] " "
		volume[endpoint] = vol_arr[2];
		if (split(vol_arr[1], user_host, "@") == 2) {
			ssh_user[endpoint] = user_host[1]
			ssh_host[endpoint] = user_host[2]
		} else ssh_host[arg] = vol_arr[1]

	} else volume[endpoint] = vol_arr[1]
	zfs[endpoint] = ssh_command[endpoint] "zfs "
	return zfs[enndpoint]
}

function h_num(num) {
	suffix = "B"
	divisors = "KMGTPE"
	for (h = 1; h <= length(divisors) && num >= 1024; h++) {
		num /= 1024
		suffix = substr(divisors, h, 1)
	}
	return int(num) suffix
}

function dry_run(command) {
	if (c["DRY_RUN"]) {
		if (command) print "+ "command
		return 1
	} else { return 0 }
}

function json_output() {
	print "{"
#  "sourceHost": "source-host-name",
#  "sourceDataset": "source-dataset-name",
#  "targetHost": "target-host-name",
#  "targetDataset": "target-dataset-name",
#  "dataAttemptedBytes": 123456789,
#  "sentStreams": [
#    "stream1@snapshot1",
#    "stream2@snapshot2"
#  ],
#  "receivedStreams": [
#    "stream1@snapshot1",
#    "stream2@snapshot2"
#  ],
#  "errorCode": 0,
#  "errorMessages": [
#    "Error message 1",
#    "Error message 2"
#  ],
#  "datestamp": "Unix-timestamp-ms",
#  "transferTimeMs": 12345
#}
#
	print "]"
}

function pipe_output() {
	if (ZELTA_PIPE) print received_streams, total_bytes, total_time, error_code 
	return error_code
}

function fail(error_code, message) {
	error(message)
	pipe_output()
	exit error_code
}

function replicate(command) {
	while (command | getline) {
		if ($1 == "incremental" || $1 == "full") { sent_streams++ }
		else if ($1 == "received") { received_streams++ }
		else if (($1 == "size") && $2) {
			verbose("sending " h_num($2) ": " source_stream[i])
			total_bytes += $2
		} else if ($3 == "real") { total_time += $2 }
		else if (/cannot/ || !/stream/) {
			print "error: " $0 | "cat 1>&2"
			error_code = 2
		}
	}
	close(command)
}

BEGIN {
	FS="\t"
	load_config()
	received_streams = 0
	total_bytes = 0
	total_time = 0
	error_code = 0

	get_endpoint_info(source)
	get_endpoint_info(target)
	zfs_send_command = zfs[source] send_flags
	zfs_receive_command = zfs[target] recv_flags
	time_start = systime()
	while (zmatch |getline) {
		if (/error/) {
			error_code = 1
			continue
		} else if ($3 == "real") {
			total_time = $2
			continue
		} else if (! /@/) {
			# If no snapshot is given, create an empty volume
			if (! $0 == $1) fail(3, $0)
			zfs_create_command = zfs[target] "create -up " q($1) " >/dev/null 2>&1"
			if (dry_run(zfs_create_command)) continue
			if (system(zfs_create_command)) fail(4, "failed to create dataset: " q($1))
			else verbose("created parent dataset(s)")
			continue
		}
		num_streams++
		if ($3) {
			rpl_cmd[++rpl_num] = zfs_send_command intr_flags q($1) " " q($2) " | " zfs_receive_command q($3)
			source_stream[rpl_num] = q($1) " to " q($2)
		} else {
			rpl_cmd[++rpl_num] = zfs_send_command q($1) " | " zfs_receive_command q($2)
			source_stream[rpl_num] = q($1)
		}
	}
	close(zmatch)

	if (!num_streams) { 
		if (!pipe_output()) verbose("nothing to replicate")
		exit error_code
	}

	FS = "[ \t]+";
	received_streams = 0
	total_bytes = 0
	for (r = 1; r <= rpl_num; r++) {
		if (dry_run(rpl_cmd[r])) {
			sub(/ \| .*/, ">/dev/null", rpl_cmd[r])
		}
		if (full_cmd) close(full_cmd)
		full_cmd = "/usr/bin/time sh -c '" rpl_cmd[r] "' 2>&1"
		replicate(full_cmd)
		if (c["REPLICATE_NEW"]) { break } # If -R is given, skip manual descendants
	}

	# Negative errors show the number of missed streams, otherwise show error code
	stream_diff = received_streams - sent_streams
	error_code = (error_code ? error_code : stream_diff)
	verbose(h_num(total_bytes) " sent, " received_streams "/" sent_streams " streams received in " total_time " seconds")
	pipe_output()
	exit error_code
}
