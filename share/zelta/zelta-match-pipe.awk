#!/usr/bin/awk -f
#
# zelta-match-pipe.awk - compares a snapshot list
#
# usage: compares two "zfs list" commands; one "zfs list" is piped for parrallel
# processing.
# 
# Reports on the relationship between two dataset trees.
#
# Child snapshot names are provided relative to the target using a trimmed dataset
# referred to as a RELNAME. For example, when zmatch is called with tank/dataset, 
# tank/dataset/child's snapshots will be reported as "/child@snapshot-name".
#
# Development notes:
#
# In code, the relative path name is referred to as a "stub."

function env(env_name, var_default) {
	return ( (env_name in ENVIRON) ? ENVIRON[env_name] : var_default )
}

function report(level, message) {
	if (!message) return 0
	if ((level <= LOG_LEVEL) && (level <= LOG_WARNING)) {
		error_messages++
		print message > STDERR
	}
	else if (level <= LOG_LEVEL) print message
}

function h_num(num) {
	if (PARSABLE) return num
	suffix = "B"
	divisors = "KMGTPE"
	for (h = 1; h <= length(divisors) && num >= 1024; h++) {
		num /= 1024
		suffix = substr(divisors, h, 1)
	}
	return int(num) suffix
}

function arrlen(array) {
	element_count = 0
	for (key in array) element_count++
	return element_count
}

function input_has_dataset() {
	if (/^real[ \t]+[0-9]/) {
		split($0, time_arr, /[ \t]+/)
		zfs_list_time += time_arr[2]
		return 0
	} else if (/(sys|user)[ \t]+[0-9]/) return 0
	else if (/dataset does not exist/) return 0
	else if ($2 ~ /^[0-9]+$/) return 1
	else {
		report(LOG_ERROR,$0)
		exit_code = 1
		return 0
	}
}

function process_dataset(endpoint) {
	stub = ($1 == dataset[endpoint]) ? "" : substr($1, ds_name_length[endpoint])
	name[endpoint,stub] = $1
	if (!stub_list[stub]++) stub_order[++stub_num] = stub
	if (!status[stub]) status[stub] = "NOSNAP"
	if (!num_snaps[endpoint,stub]) num_snaps[endpoint,stub] = 0
	written[endpoint,stub] += $3
	total_written[endpoint] += $3
}

function process_snapshot(endpoint) {
	snapshot_stub = substr($1, ds_name_length[endpoint])	# [child]@snapshot
	guid[endpoint,snapshot_stub] = $2	# GUID property
	written[endpoint,snapshot_stub] = $3	# written property
	split(snapshot_stub, split_stub, "@")
	stub = split_stub[1]			# [child] (blank for top dataset name)
	snapshot_name = "@" split_stub[2]	# @snapshot
	# First, Last, and Count of snapshots
	if (!num_snaps[endpoint,stub]++) last[endpoint,stub] = snapshot_name
	first[endpoint,stub] = snapshot_name
}

function get_snapshot_data(endpoint) {
	if (input_has_dataset()) {
		if ($1 ~ /@/) { 
			process_snapshot(endpoint)
			return 1
		} else process_dataset(endpoint)
	}
}

function check_parent() {
	if (!(snapshot_list_command ~ /zfs list/)) return 0
	parent = dataset[target]
	if (!gsub(/\/[^\/]+$/, "", parent)) {
		report(LOG_ERROR,"invalid target: " parent)
		exit 1
	}
	parent_list_command = snapshot_list_command
	sub(/zfs list.*'/, "zfs list '"parent"'", parent_list_command)
	parent_list_command | getline parent_check
	if (parent_check ~ /dataset does not exist/) {
		report(LOG_DEFAULT, "parent dataset does not exist: " parent)
	}
	close(parent_list_command)
}

function arr_sort(arr) {
    n = arrlen(arr);
    for (i = 2; i <= n; i++) {
        # Store the current value and its key
        value = arr[i];
        j = i - 1;
        while (j >= 1 && arr[j] > value) {
            arr[j + 1] = arr[j];
            j--;
        }
        arr[j + 1] = value;
    }
}

function add_prop_col(prop) {
	PROP_LIST[++PROP_NUM] = prop
	PROP_DICT[prop] = PROP_NUM
}
	
function check_prop_col(prop) {
	prop = tolower(prop)
	gsub(/_/, "", prop)
	if (prop ~ /^(relname|name|stub)/) add_prop_col("REL_NAME")
	else if (prop == "status") add_prop_col("STATUS")
	else if (prop == "action") add_prop_col("ACTION")
	else if (prop == "match") add_prop_col("MATCH")
	else if (prop == "xfersize") add_prop_col("XFER_SIZE")
	else if (prop == "xfernum") add_prop_col("XFER_NUM")
	else if (prop == "nummatches") add_prop_col("NUM_MATCHES")
	else if (prop == "srcname") add_prop_col("SRC_NAME")
	else if (prop == "srcfirst") add_prop_col("SRC_FIRST")
	else if (prop == "srcnext") add_prop_col("SRC_NEXT")
	else if (prop == "srclast") add_prop_col("SRC_LAST")
	else if (prop == "srcwritten") add_prop_col("SRC_WRITTEN")
	else if (prop == "tgtsnaps") add_prop_col("TGT_SNAPS")
	else if (prop == "tgtname") add_prop_col("TGT_NAME")
	else if (prop == "tgtfirst") add_prop_col("TGT_FIRST")
	else if (prop == "tgtnext") add_prop_col("TGT_NEXT")
	else if (prop == "tgtlast") add_prop_col("TGT_LAST")
	else if (prop == "tgtwritten") add_prop_col("TGT_WRITTEN")
	else if (prop == "tgtsnaps") add_prop_col("TGT_SNAPS")
	else if (prop == "info") add_prop_col("INFO")
	else print "error: unknown property " prop
}
	
function property_list() {
	PROPERTIES_ALL = "rel_name,status,action,match,xfer_size,xfer_num,num_matches,src_name,src_first,src_next,src_last,src_snaps,src_written,tgt_name,tgt_first,tgt_next,tgt_last,tgt_written"
	PROPERTIES_LIST_DEFAULT = "rel_name,status,action,match,src_first,src_next,src_last,tgt_last"
	PROPERTIES_MATCH_DEFAULT = "rel_name,info"
	properties = env("ZELTA_MATCH_PROPERTIES", PROPERTIES_MATCH_DEFAULT)
	if (properties == "all") properties = PROPERTIES_ALL
	else if (properties == "list") properties = PROPERTIES_LIST_DEFAULT
	prop_num = split(properties, prop_list, /,/)
	for (p=1;p<=prop_num;p++) check_prop_col(prop_list[p])
}

BEGIN {
	FS="\t"
	OFS="\t"
	STDERR = "/dev/stderr"
	LOG_ERROR=-2
	LOG_WARNING=-1
	LOG_DEFAULT=0
	LOG_VERBOSE=1
	LOG_VV=2
	LOG_LEVEL = env("ZELTA_LOG_LEVEL", 0)

	MODE = "CHART"
	PASS_FLAGS = env("ZELTA_MATCH_FLAGS", "")
	if (PASS_FLAGS ~ /p/) PARSABLE++
	if (PASS_FLAGS ~ /q/) LOG_LEVEL--
	if (PASS_FLAGS ~ /H/) {
		NOHEADER++
		MODE = "ONETAB"
	}
	if (PASS_FLAGS ~ /v/) LOG_LEVEL++

	property_list()

	exit_code = 0
	LOG_MODE = ZELTA_PIPE ? 0 : 1
	target_zfs_list_time = 0
}

function get_endpoint_info() {
	endpoint = $1
	endpoint_hash[endpoint] = $1
	dataset[endpoint] = $2
	ds_name_length[endpoint] = length(dataset[endpoint]) + 1
	return endpoint
}

function count_snapshot_diff() {
	transfer_size += snapshot_written
	xfersize[stub] += snapshot_written
	xfersnaps[stub]++
}

NR == 1 { source = get_endpoint_info() }

NR == 2 { target = get_endpoint_info() }

NR == 3 {
	zfs_list_time = 0
	transfer_size = 0
	if (!target) next
	snapshot_list_command = $0;
	if ((source == target) || !snapshot_list_command) {
		report(LOG_WARNING, "identical source and target")
	} else {
		# Load target snapshots
		while  (snapshot_list_command | getline) get_snapshot_data(target)
		close(snapshot_list_command)
	}
	target_zfs_list_time = zfs_list_time
}

NR > 3 {
	if (!get_snapshot_data(source)) { next }
	if (stub in matches) next
	else if (!last[target,stub] && !(stub in new_dataset)) {
		if (!stub) check_parent()
		new_dataset[stub] = snapshot_name
		if (written[target,stub]) status[stub] = "MISMATCH"
		else if (num_snaps[target,stub] == "0") status[stub] = "NO_MATCH"
		else {
			status[stub] = "SRC_ONLY"
			count_snapshot_diff()
		}
	} else if (guid[target,snapshot_stub]) {
		if (guid[target,snapshot_stub] == guid[source,snapshot_stub]) {
			matches[stub] = snapshot_name
			if (snapshot_stub == last[source,stub]) {
				#basic_log[stub] = "target has latest source snapshot: " snapshot_stub
				status[stub] = (snapshot_stub == last[target,stub]) ? "SYNCED" : "AHEAD"
			} else if (guid_error[stub]) {
				# report(LOG_VERBOSE,"latest guid match: " snapshot_stub)
				status[stub] = "MISMATCH"
			} else {
				status[stub] = "BEHIND"
				#basic_log[stub] = "match: " snapshot_stub OFS "latest: " source_latest[stub]
			}
		} else {
			report(LOG_VERBOSE,"guid mismatch: " snapshot_stub)
			#warning_log[stub] = warning_log[stub] "guid mismatch on: " snapshot_stub "\n"
			guid_error[stub]++
		}
	} else count_snapshot_diff()
}

function summarize() {
	if (status[stub]=="SYNCED") s = "up-to-date"
	else if (status[stub]=="SRC_ONLY") s = "syncable, new dataset"
	else if ((status[stub]=="BEHIND") && written[source,stub]) s = "target is written"
	else if (status[stub]=="BEHIND") s = "syncable"
	else if (status[stub]=="TGT_ONLY") s = "no source dataset"
	else if (status[stub]=="AHEAD") s = "target is ahead"
	else if (status[stub]=="NOSNAP") s = "no source snapshots"
	else if (status[stub]=="NOMATCH") s = "target has no snapshots"
	else if (status[stub]=="ORPHAN") s = "no parent snapshot"
	else if (guid_error[stub]) s = "guid mismatch"
	else s = "match, but latest snapshots differ"
	return s
}

function print_row(cols) {
	num_col = arrlen(cols)
	for(c=1;c<=num_col;c++) {
		if (MODE=="ONETAB") printf ((c>1)?"\t":"") cols[c]
		if (MODE=="CHART") printf ((c>1)?"  ":"") pad[c], cols[c]
	}
	printf "\n"
}

function make_header_column(title, arr, endpoint) {
	columns[cnum] = NOHEADER?"  ":toupper(title)
	if (MODE=="CHART") { 
		width = length(title)
		for (w in arr) {
			if (!endpoint || index(w, endpoint) == 1) {
				if (length(arr[w])>width) width = length(arr[w])
			}
		}
		pad[cnum] = "%-"width"s"
	}
}

function chart_header() {
	for (cnum=1;cnum<=PROP_NUM;cnum++) {
		col = PROP_LIST[cnum]
		if ("REL_NAME" == col) make_header_column(col, stub_order)
		if ("STATUS" == col) make_header_column(col, status)
		if ("ACTION" == col) make_header_column(col, action)
		if ("XFER_SIZE" == col) make_header_column(col, xfersize)
		if ("XFER_NUM" == col) make_header_column(col, xfersnaps)
		if ("MATCH" == col) make_header_column(col, matches)
		if ("NUM_MATCHES" == col) make_header_column(col, num_matches)
		if ("SRC_NAME" == col) make_header_column(col, name, source)
		if ("SRC_FIRST" == col) make_header_column(col, first, source)
		if ("SRC_NEXT" == col) make_header_column(col, src_next)
		if ("SRC_LAST" == col) make_header_column(col, last, source)
		if ("SRC_WRITTEN" == col) make_header_column(col, written, source)
		if ("SRC_SNAPS" == col) make_header_column(col, num_snaps)
		if ("TGT_NAME" == col) make_header_column(col, name, target)
		if ("TGT_FIRST" == col) make_header_column(col, first, target)
		if ("TGT_NEXT" == col) make_header_column(col, tgt_next)
		if ("TGT_LAST" == col) make_header_column(col, last, target)
		if ("TGT_WRITTEN" == col) make_header_column(col, written, target)
		if ("TGT_SNAPS" == col) make_header_column(col, num_snaps, target)
		if ("INFO" == col) make_header_column(col, summary)
	}
	print_row(columns)
}

function chart_row(field) {
	if (!ROW++ && !(MODE == "ONETAB")) chart_header()
	delete columns
	for (cnum=1;cnum<=PROP_NUM;cnum++) {
		col = PROP_LIST[cnum]
		if ("REL_NAME" == col) columns[cnum] = field
		if ("STATUS" == col) columns[cnum] = status[field]
		if ("ACTION" == col) columns[cnum] = action[field]
		if ("XFER_SIZE" == col) columns[cnum] = h_num(xfersize[field])
		if ("XFER_NUM" == col) columns[cnum] = xfersnaps[field]
		if ("MATCH" == col) columns[cnum] = matches[field]
		if ("NUM_MATCHES" == col) columns[cnum] = num_matches[field]
		if ("SRC_NAME" == col) columns[cnum] = name[source,field]
		if ("SRC_FIRST" == col) columns[cnum] = first[source,field]
		if ("SRC_NEXT" == col) columns[cnum] = src_next[field]
		if ("SRC_LAST" == col) columns[cnum] = last[source,field]
		if ("SRC_WRITTEN" == col) columns[cnum] = h_num(written[source,field])
		if ("SRC_SNAPS" == col) columns[cnum] = num_snaps[source,field]
		if ("TGT_NAME" == col) columns[cnum] = name[target,field]
		if ("TGT_FIRST" == col) columns[cnum] = first[target,field]
		if ("TGT_NEXT" == col) columns[cnum] = tgt_next[field]
		if ("TGT_LAST" == col) columns[cnum] = last[target,field]
		if ("TGT_WRITTEN" == col) columns[cnum] = h_num(written[target,field])
		if ("TGT_SNAPS" == col) columns[cnum] = num_snaps[target,field]
		if ("INFO" == col) columns[cnum] = summary[field]
	}
	print_row(columns)
}

END {
	for (stub in stub_list) {
		if ((matches[stub] != last[source,stub]) && (matches[stub] != last[target,stub])) {
			status[stub] = "MISMATCH"
		}
		if (stub && (status[stub] == "SRC_ONLY")) {
			parent_stub = stub
			sub(/\/[^\/]+$/, "", parent_stub)
			if (!last[source,parent_stub]) status[stub] = "ORPHAN"
		} else if (status[stub] == "NOSNAP") {
		       if (num_snaps[source,stub] == "") status[stub] = "TGT_ONLY"
		} else if (status[stub] == "SYNCED") count_synced++
		else if ((status[stub] == "SRC_ONLY") || (status[stub] == "BEHIND")) count_ready++
		else count_nomatch++
		summary[stub] = summarize()
		if (last[source,stub] == last[target,stub]) xfersnaps[stub] = 0
	}
	if (LOG_LEVEL >= 0) {
		arr_sort(stub_order)
		for (i=1;i<=arrlen(stub_order);i++) chart_row(stub_order[i])
	}
	source_zfs_list_time = zfs_list_time
	count_stub = arrlen(stub_list)
	if (MODE=="ONETAB") print "SOURCE_LIST_TIME:", source_zfs_list_time, ":","TARGET_LIST_TIME", target_zfs_list_time
	else {
		if (arrlen(source_latest) == 0) report(LOG_WARNING, "no source snapshots found")
		else if (count_stub == count_synced) report(LOG_DEFAULT, count_stub " datasets synced")
		else if (count_stub == count_ready) report(LOG_DEFAULT, count_stub " datasets syncable")
		else if (count_stub == count_nomatch) report(LOG_WARNING, count_stub " datasets unsyncable")
		else {
			log_msg = count_stub " total datasets"
			log_msg = log_msg (count_synced?", "count_synced" synced":"")
			log_msg = log_msg (count_ready?", "count_ready" syncable":"")
			log_msg = log_msg (count_nomatch?", "count_nomatch" unsyncable":"")
			report(LOG_WARNING, log_msg)
		}
		if (total_written[target]) report(LOG_WARNING, "target dataset has changed: " h_num(total_written[target]))
		if (total_written[source]) report(LOG_WARNING, "source dataset has changed: " h_num(total_written[source]))
		if (transfer_size) report(LOG_DEFAULT, "snapshot syncable transfer size: " h_num(transfer_size))
	}
	if (error_messages) close(STDERR)
}
