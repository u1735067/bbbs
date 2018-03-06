#!/usr/bin/env bash

bbbs_user_name=borg
bbbs_prog_name=bbbs

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
#       http://www.brynosaurus.com/cachedir/"

bbbs_retrieve_check() {
	# Check if required commands are present
	if [ ! $(command -v curl) ]; then echo "ERROR: curl is missing"; exit 1; fi
	if [ ! $(command -v jq) ]; then echo "ERROR: jq is missing"; exit 1; fi
	if [ ! $(command -v gpg) ]; then echo "ERROR: gpg is missing"; exit 1; fi

	tmpdir=$(mktemp --directory)
	pushd "$tmpdir" > /dev/null

	echo "-- Retrieving binary & signature"
	curl --silent https://api.github.com/repos/borgbackup/borg/releases/latest \
		| jq --raw-output '.assets[] | select(.name as $asset | ["'$borg_exec'", "'$borg_exec_sig'"] | index($asset)) | .browser_download_url' \
		| xargs --max-args=1 --max-procs=2 curl --silent --location --remote-name

	echo "-- Checking signature"

	# https://borgbackup.readthedocs.io/en/stable/support.html
	gpg --homedir "$tmpdir" --no-default-keyring --quiet --batch --keyid-format 0xlong --keyserver pgp.mit.edu --recv-keys 6D5BEF9ADD2075805747B70F9F88FB52FAF7B393
	gpg --homedir "$tmpdir" --no-default-keyring --quiet --batch --keyid-format 0xlong --trusted-key 0x9F88FB52FAF7B393 --verify "$borg_exec_sig" "$borg_exec"
	sig_valid=$?
	if [ ! $sig_valid -eq 0 ]; then
		echo "Binary signature could not be verified (files are left in $tmpdir)."
		exit
	fi

	echo "-- Moving executable"
	mkdir --parents "$bbbs_opt_path" 2> /dev/null
	mv "$borg_bin" "${borg_bin}.old" 2> /dev/null
	mv "$borg_exec" "$borg_bin"
	chmod +x "$borg_bin"
	popd > /dev/null
	rm -rf "$tmpdir"
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
	ln -s "$dir_conf" "${dir_home}/.config/borg"
	ln -s "$dir_cache" "${dir_home}/.cache/borg"
	ln -s "${dir_home}/.ssh" "${dir_home}/ssh"
	#chown --reference "$dir_home" $borg_bin
	chmod --recursive go-rwx "$dir_home"
	chown --recursive --reference "$dir_home" "$dir_home"
	# On clients, new files will be owned by root .. but whatever, as long as they're not readable by others ..

	echo "-- Adding sudoers rules"
	sudo_rules="\
# BBBS client
Defaults:${bbbs_user_name} env_keep += \"BORG_*\"
${bbbs_user_name} ALL=(root,backup : root,backup) NOPASSWD: /opt/${bbbs_prog_name}/bbbs-client create *
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
	ln -s "$dir_conf" "${dir_home}/.config/borg"
	ln -s "$dir_cache" "${dir_home}/.cache/borg"
	ln -s "${dir_home}/.ssh" "${dir_home}/ssh"
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
	bbbs_retrieve_check
	echo "- Done."
}

bbbs_uninstall() {
	echo "- Uninstalling BBBS"

	echo "-- Removing executable and cache"
	rm -rf "$bbbs_opt_path" "$dir_cache"

	echo "-- Removing sudoers rules"
	if [ -f "/etc/sudoers.d/${bbbs_prog_name}" ]; then
		rm -f "/etc/sudoers.d/${bbbs_prog_name}"
	else
		echo " > /etc/sudoers.d/${bbbs_prog_name} wasn't found, please check BBBS related entries are removed"
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
