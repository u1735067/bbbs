#!/usr/bin/env bash

bbbs_user_name=borg
bbbs_prog_name=bbbs

#borg_branch=1.1.
borg_exec=borg-linux64
borg_exec_sig=borg-linux64.asc

bbbs_opt_path="/opt/${bbbs_prog_name}"
borg_bin="${bbbs_opt_path}/borg.bin"

dir_cache="/var/cache/${bbbs_prog_name}"

cache_tag_name="CACHEDIR.TAG"
cache_tag_content="\
Signature: 8a477f597d28d172789f06886806bc55
# This file is a cache directory tag created by Borg.
# For information about cache directory tags, see:
#       http://www.brynosaurus.com/cachedir/
"

_bbbs_retrieve_check() {
	# Check if required commands are present
	if [ ! $(command -v curl) ]; then echo "ERROR: curl is missing"; return 1; fi
	if [ ! $(command -v jq) ]; then echo "ERROR: jq is missing"; return 1; fi
	if [ ! $(command -v gpg) ]; then echo "ERROR: gpg is missing"; return 1; fi

	tmpdir=$(mktemp --directory)
	pushd "$tmpdir" > /dev/null

	echo "-- Retrieving binary & signature"
	# "Tagged Latest release", to use with https://api.github.com/repos/borgbackup/borg/releases/latest
	#jq_filter='.assets[] | select(.name as $asset | ["'$borg_exec'", "'$borg_exec_sig'"] | index($asset)) | .browser_download_url'
	# "Last version number in branch"
	#jq_filter='[.[] | select((.prerelease or .draft | not) and (.tag_name | startswith("'$borg_branch'")))]
	#			| max_by(.tag_name | split(".") | map(tonumber)) | .assets[]
	#			| select(.name as $asset | ["'$borg_exec'", "'$borg_exec_sig'"] | index($asset)) | .browser_download_url'
	# "Last version number"
	jq_filter='[.[] | select(.prerelease or .draft | not)] | max_by(.tag_name | split(".") | map(tonumber)) | .assets[] '"\
				"'| select(.name as $asset | ["'$borg_exec'", "'$borg_exec_sig'"] | index($asset)) | .browser_download_url'
	curl --silent --show-error "https://api.github.com/repos/borgbackup/borg/releases" \
		| jq --raw-output "$jq_filter" 2>/dev/null | while read url; do echo $url; echo $url >&2; done \
		| xargs curl --location --remote-name-all # --progress-bar could be used too

	echo "-- Checking signature"
	# https://borgbackup.readthedocs.io/en/stable/support.html
	# https://superuser.com/questions/227991/where-to-upload-pgp-public-key-are-keyservers-still-surviving
	gpg --homedir "$tmpdir" --no-default-keyring --quiet --batch --keyid-format 0xlong --keyserver "hkp://pool.sks-keyservers.net" --recv-keys 0x6D5BEF9ADD2075805747B70F9F88FB52FAF7B393
	gpg --homedir "$tmpdir" --no-default-keyring --quiet --batch --keyid-format 0xlong --trusted-key 0x9F88FB52FAF7B393 --verify "$borg_exec_sig" "$borg_exec"
	if [ ! $? -eq 0 ]; then
		echo "Binary signature could not be verified (files are left in $tmpdir)."
		return 1
	fi

	echo "-- Moving executable"
	mkdir --parents "$bbbs_opt_path" 2> /dev/null
	mv "$borg_bin" "${borg_bin}.old" 2> /dev/null
	mv "$borg_exec" "$borg_bin"
	chmod +x "$borg_bin"
	popd > /dev/null
	rm -rf "$tmpdir"

	return 0
}

bbbs_retrieve_check() {
	if ! _bbbs_retrieve_check || [ ! -x "$borg_bin" ]; then
		echo "The script failed to retrieve or verify borg binary, you'll have to do it yourself, or you can abort and retry"
		read -rn1 -p "Do you want to continue? [yN]: " skip_bin
		echo
		if ! [ "$skip_bin" = 'y' -o "$skip_bin" = 'Y' ]; then
			echo "Exiting"
			exit 1
		fi
	fi
}

bbbs_install_client() {
	echo "- Installing BBBS (client)"

	# Ideally, the server version should be pushed
	bbbs_retrieve_check

	echo "-- Creating user"
	(getent group backup > /dev/null) && gid="--gid backup" || gid=
	useradd --system --create-home $gid --shell "/bin/bash" --skel /dev/null --password '*' --comment "Bash Borg Backup System" "$bbbs_user_name"

	dir_home=$(getent passwd "$bbbs_user_name" | cut -d: -f6)
	dir_conf="$dir_home"
	#dir_keys="$dir_conf"/keys
	#dir_security="$dir_conf"/security
	dir_cache="${dir_home}/cache"

	echo "-- Setting up directories"
	if [ ! -d "$dir_home" ]; then
		echo "User not created ?"
		exit
	fi
	mkdir "${dir_home}/.config" "${dir_home}/.cache" "${dir_home}/.ssh" "$dir_cache"
	echo "$cache_tag_content" > "${dir_cache}/${cache_tag_name}"
	ln -s "../" "${dir_home}/.config/borg"
	#ln -s "$dir_conf" "${dir_home}/.config/borg"
	ln -s "../cache/" "${dir_home}/.cache/borg"
	#ln -s "$dir_cache" "${dir_home}/.cache/borg"
	ln -s ".ssh/" "${dir_home}/ssh"
	#ln -s "${dir_home}/.ssh" "${dir_home}/ssh"
	#chown --reference "$dir_home" $borg_bin
	chmod --recursive go-rwx "$dir_home"
	chown --recursive --reference "$dir_home" "$dir_home"
	# On clients, new files will be owned by root .. but whatever, as long as they're not readable by others ..

	echo "-- Adding sudoers rules"
	sudo_rules="\
# BBBS client
Defaults:${bbbs_user_name} env_keep += \"BORG_*\"
${bbbs_user_name} ALL=(root,backup : root,backup) NOPASSWD: /opt/${bbbs_prog_name}/bbbs-client create*
"
	if [ -d "/etc/sudoers.d" -a ! -e "/etc/sudoers.d/${bbbs_prog_name}" ]; then
		echo "$sudo_rules" > "/etc/sudoers.d/${bbbs_prog_name}"
	else
		cat <<EOF

 > The following sudoers (run visudo) rules are required, it allows the user ${bbbs_user_name}
to run /opt/${bbbs_prog_name}/borg.bin as root (with BORG_* environment variables kept):

$sudo_rules
EOF
	fi

	echo "- Done."
}

bbbs_install_server() {
	dir_home="/var/opt/${bbbs_prog_name}"
	dir_conf="$dir_home"
	#dir_keys="$dir_conf"/keys
	#dir_security="$dir_conf"/security

	echo "- Installing BBBS (server)"

	bbbs_retrieve_check

	echo "-- Creating user"
	(getent group backup > /dev/null) && gid="--gid backup" || gid=
	useradd --system --create-home --home-dir "$dir_home" $gid --shell "/bin/bash" --skel /dev/null --password '*' --comment "Bash Borg Backup System" "$bbbs_user_name"

	echo "-- Setting up directories"
	if [ ! -d "$dir_home" ]; then
		echo "User not created ?"
		exit
	fi
	mkdir "${dir_home}/.config" "${dir_home}/.cache" "${dir_home}/.ssh" "$dir_cache"
	echo "$cache_tag_content" > "${dir_cache}/${cache_tag_name}"
	ln -s "../" "${dir_home}/.config/borg"
	#ln -s "$dir_conf" "${dir_home}/.config/borg"
	ln -s "$dir_cache" "${dir_home}/.cache/borg"
	ln -s ".ssh/" "${dir_home}/ssh"
	#ln -s "${dir_home}/.ssh" "${dir_home}/ssh"
	chmod --recursive go-rwx "$dir_home" "$dir_cache"
	chown --recursive --reference "$dir_home" "$dir_home" "$dir_cache"
	#chown --reference "$dir_home" $borg_bin

	echo "-- Adding sudoers rules"
	sudo_rules="\
# BBBS server
Defaults>${bbbs_user_name} env_keep += \"BORG_* BORGW_* SSH_*\"
root,%sudo,%wheel ALL=(${bbbs_user_name}) NOPASSWD: /opt/${bbbs_prog_name}/borg
root,%sudo,%wheel ALL=(${bbbs_user_name}) NOPASSWD: /opt/${bbbs_prog_name}/ssh-wrapper-server
"
	if [ -d "/etc/sudoers.d" -a ! -e "/etc/sudoers.d/${bbbs_prog_name}" ]; then
		echo "$sudo_rules" > "/etc/sudoers.d/${bbbs_prog_name}"
	else
		cat <<EOF

 > The following sudoers (run visudo) rules are required, it allows the admins
to run /opt/${bbbs_prog_name}/borg.bin and the server wrapper as ${bbbs_user_name} (keeping required 
environment variables):

$sudo_rules
EOF
	fi

	echo "- Done."
}

bbbs_update() {
	echo "- Updating BBBS"

	echo "-- Pulling scripts"
	pushd $(cd -P -- "$(dirname -- "$0")" && pwd -P) > /dev/null
	git pull
	popd > /dev/null

	bbbs_retrieve_check

	echo "- Done."
}

bbbs_uninstall() {
	echo "- Uninstalling BBBS"

	echo "-- Removing executable"
	rm -rf "$bbbs_opt_path"

	echo "-- Removing sudoers rules"
	if [ -f "/etc/sudoers.d/${bbbs_prog_name}" ]; then
		rm -f "/etc/sudoers.d/${bbbs_prog_name}"
	else
		echo " > /etc/sudoers.d/${bbbs_prog_name} wasn't found, please check BBBS related entries are removed"
	fi

	# That's only on the server: on clients the cache is in user dir
	if [ -d "$dir_cache" ]; then
		echo "-- Removing cache"
		rm -rf "$dir_cache"
	fi
}

bbbs_uninstall_with_user() {
	bbbs_uninstall

	echo "-- Removing user and homedir"
	userdel --remove "$bbbs_user_name"

	echo "- Done."
}

case "$1" in
	install-client)
		bbbs_install_client
		;;
	install-server)
		bbbs_install_server
		;;
	update)
		bbbs_update
		;;
	uninstall)
		bbbs_uninstall
		echo "- Done."
		;;
	uninstall-with-user)
		bbbs_uninstall_with_user
		;;
	*)
		echo "Usage: $0 [install-client|install-server|update|uninstall|uninstall-with-user]" >&2
		exit 3
	;;
esac
