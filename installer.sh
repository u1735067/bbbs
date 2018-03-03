#!/usr/bin/env bash

borg_exec=borg-linux64
borg_exec_sig=borg-linux64.asc

borg_user=borg
dir_exec=/opt/borg
borg_bin=$dir_exec/borg.bin

dir_cache=/var/cache/borg

borg_retrieve_check() {
	# Check if required commands are present
	if [ ! $(command -v curl) ]; then echo "ERROR: curl is missing"; exit 1; fi
	if [ ! $(command -v jq) ]; then echo "ERROR: jq is missing"; exit 1; fi
	if [ ! $(command -v gpg) ]; then echo "ERROR: gpg is missing"; exit 1; fi

	tmpdir=$(mktemp --directory)
	pushd $tmpdir > /dev/null

	echo "-- Retrieving binary & signature"
	curl --silent https://api.github.com/repos/borgbackup/borg/releases/latest \
	  | jq --raw-output '.assets[] | select(.name as $asset | ["'$borg_exec'", "'$borg_exec_sig'"] | index($asset)) | .browser_download_url' \
	  | xargs --max-args=1 --max-procs=2 curl --silent --location --remote-name

	echo "-- Checking signature"

	# https://borgbackup.readthedocs.io/en/stable/support.html
	gpg --homedir $tmpdir --no-default-keyring --quiet --batch --keyid-format 0xlong --keyserver pgp.mit.edu --recv-keys 6D5BEF9ADD2075805747B70F9F88FB52FAF7B393
	gpg --homedir $tmpdir --no-default-keyring --quiet --batch --keyid-format 0xlong --trusted-key 0x9F88FB52FAF7B393 --verify "$borg_exec_sig" "$borg_exec"
	sig_valid=$?
	if [ ! $sig_valid -eq 0 ]; then
	  echo "Binary signature could not be verified (files are left in $tmpdir)."
	  exit
	fi

	echo "-- Moving executable"
	mkdir --parents $dir_exec 2> /dev/null
	mv $borg_bin $borg_bin".old" 2> /dev/null
	mv $borg_exec $borg_bin
	chmod +x $borg_bin
	popd > /dev/null
	rm -rf $tmpdir
}

borg_install_client() {
	echo "- Installing Borg (client)"
	# Ideally, the server version should be pushed
	borg_retrieve_check

	echo "-- Creating user"
	$(grep '^backup:' /etc/group > /dev/null) && gid="--gid backup" || gid=
	useradd --system --create-home $gid --shell "/bin/bash" --skel /dev/null --password '*' $borg_user

	dir_home=~borg
	dir_conf=$dir_home
	#dir_keys=$dir_conf/keys
	#dir_security=$dir_conf/security
	dir_cache=$dir_home/cache

	echo "-- Setting up directories"
	if [ ! -d "$dir_home" ]; then
		echo "User not created ?"
		exit
	fi
	mkdir "$dir_home/.config" "$dir_home/.cache" "$dir_home/.ssh" "$dir_cache"
	ln -s "$dir_conf" "$dir_home/.config/borg"
	ln -s "$dir_cache" "$dir_home/.cache/borg"
	ln -s "$dir_home/.ssh" "$dir_home/ssh"
	chown --reference "$dir_home" $borg_bin
	chown --recursive --reference "$dir_home" "$dir_home"

	echo "-- Adding sudoers rules"
	sudo_rules="\
# Borg client
Defaults:borg env_keep += \"LANG BORG_*\"
borg ALL=(root,backup : root,backup) NOPASSWD: /opt/borg/borg-client create *
"
	if [ -d "/etc/sudoers.d" -a ! -e "/etc/sudoers.d/borg" ]; then
		echo "$sudo_rules" > "/etc/sudoers.d/borg"
	else
		cat <<EOF

 > The following sudoers (run visudo) rules are required, it allows the user borg
to run /opt/borg/borg.bin as root (with BORG_* environment variables kept):

$sudo_rules
EOF
	fi

	echo "- Done."
}

borg_install_server() {
	dir_home=/var/opt/borg
	dir_conf=$dir_home
	#dir_keys=$dir_conf/keys
	#dir_security=$dir_conf/security

	echo "- Installing Borg (server)"
	borg_retrieve_check

	echo "-- Creating user"
	$(grep '^backup:' /etc/group > /dev/null) && gid="--gid backup" || gid=
	useradd --system --create-home --home-dir "$dir_home" --gid backup --shell "/bin/bash" --skel /dev/null --password '*' $borg_user

	echo "-- Setting up directories"
	if [ ! -d "$dir_home" ]; then
		echo "User not created ?"
		exit
	fi
	mkdir "$dir_home/.config" "$dir_home/.cache" "$dir_home/.ssh" "$dir_cache"
	ln -s "$dir_conf" "$dir_home/.config/borg"
	ln -s "$dir_cache" "$dir_home/.cache/borg"
	ln -s "$dir_home/.ssh" "$dir_home/ssh"
	chown --reference "$dir_home" $borg_bin
	chown --recursive --reference "$dir_home" "$dir_home" "$dir_cache"

	echo "-- Adding sudoers rules"
	sudo_rules="\
# Borg server
Defaults>borg env_keep += \"BORG_* BORGW_* SSH_*\"
root,%sudo,%wheel ALL=(borg) NOPASSWD: /opt/borg/borg.bin
root,%sudo,%wheel ALL=(borg) NOPASSWD: /opt/borg/ssh-wrapper-server
"
	if [ -d "/etc/sudoers.d" -a ! -e "/etc/sudoers.d/borg" ]; then
		echo "$sudo_rules" > "/etc/sudoers.d/borg"
	else
		cat <<EOF

 > The following sudoers (run visudo) rules are required, it allows the admins
to run /opt/borg/borg.bin and the server wrapper as borg (keeping required 
environment variables):

$sudo_rules
EOF
	fi

	echo "- Done."
}

borg_update() {
	echo "- Updating Borg"
	borg_retrieve_check
	echo "- Done."
}

borg_uninstall() {
	echo "- Uninstalling Borg"
	echo "-- Removing executable and cache"
	rm -rf "$dir_exec" "$dir_cache"
	echo "-- Removing sudoers rules"
	[ -f "/etc/sudoers.d/borg" ] && rm -f "/etc/sudoers.d/borg" || \
	  echo " > /etc/sudoers.d/borg wasn't found, please check borg related entries are removed"
}

borg_uninstall_with_user() {
	borg_uninstall
	echo "-- Removing user and homedir"
	userdel --remove $borg_user
	echo "- Done."
}

case "$1" in
	install-client)
		borg_install_client
		;;
	install-server)
		borg_install_server
		;;
	update)
		borg_update
		;;
	uninstall)
		borg_uninstall
		echo "- Done."
		;;
	uninstall-with-user)
		borg_uninstall_with_user
		;;
	*)
		echo "Usage: $0 [install-client|install-server|update|uninstall|uninstall-with-user]" >&2
		exit 3
	;;
esac
