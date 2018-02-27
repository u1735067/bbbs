#!/usr/bin/env bash

borg_exec=borg-linux64
borg_exec_sig=borg-linux64.asc

borg_user=borg
dir_exec=/opt/borg
borg_bin=$dir_exec/borg.bin

dir_cache=/var/cache/borg

borg_retrieve_check() {
	tmpdir=$(mktemp --directory)
	pushd $tmpdir > /dev/null

	echo "-- Retrieving binary & signature"
	curl --silent https://api.github.com/repos/borgbackup/borg/releases/latest \
	  | jq --raw-output '.assets[] | select(.name as $asset | ["'$borg_exec'", "'$borg_exec_sig'"] | index($asset)) | .browser_download_url' \
	  | xargs --max-args=1 --max-procs=2 curl --silent --remote-name

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
	chmod u+x $borg_bin
	popd > /dev/null
	rm -rf $tmpdir
}

borg_install_client() {
	echo "- Installing Borg (client)"
	# Ideally, the server version should be pushed
	borg_retrieve_check

	echo "-- Creating user"
	useradd --system --create-home --gid backup --shell "/bin/bash" --skel /dev/null --password '*' $borg_user

	dir_home=~borg
	dir_conf=$dir_home
	#dir_keys=$dir_conf/keys
	#dir_security=$dir_conf/security
	dir_cache=$dir_home/cache

	echo "-- Seting up directories"
	if [ ! -d "$dir_home" ]; then
		echo "User not created ?"
		exit
	fi
	mkdir "$dir_home/.config" "$dir_home/.cache" "$dir_home/.ssh" "$dir_cache"
	ln -s "$dir_conf" "$dir_home/.config/borg"
	ln -s "$dir_cache" "$dir_home/.cache/borg"
	ln -s "$dir_home/.ssh" "$dir_home/ssh"
	chown $borg_user $borg_bin
	chown -R $borg_user "$dir_home"

	echo "-- Sudoers rules"
	cat <<EOF
The following sudoers (run visudo) rules are required, it allows the user borg
to run /opt/borg/borg.bin as root (with BORG_* environment variables kept):

# Borg client
Defaults:borg env_keep += "BORG_*"
borg ALL=(root backup:root backup) NOPASSWD: /opt/borg/borg.bin

EOF

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
	#adduser --system              --home "$dir_home"   --ingroup backup --shell "/bin/bash" --disabled-login .....
	useradd --system --create-home --home-dir "$dir_home" --gid backup --shell "/bin/bash" --skel /dev/null --password '*' $borg_user

	echo "-- Seting up directories"
	if [ ! -d "$dir_home" ]; then
		echo "User not created ?"
		exit
	fi
	mkdir "$dir_home/.config" "$dir_home/.cache" "$dir_home/.ssh" "$dir_cache"
	ln -s "$dir_conf" "$dir_home/.config/borg"
	ln -s "$dir_cache" "$dir_home/.cache/borg"
	ln -s "$dir_home/.ssh" "$dir_home/ssh"
	chown $borg_user $borg_bin
	chown -R $borg_user "$dir_home" "$dir_cache"

	echo "-- Sudoers rules"
	cat <<EOF
The following sudoers (run visudo) rules are required, it allows the admins
to run /opt/borg/borg.bin and the server wrapper as borg (keeping required 
environment variables):

# Borg server
Defaults>borg env_keep += "BORG_* BORGW_* SSH_*"
root,%sudo,%wheel ALL=(borg) NOPASSWD: /opt/borg/borg.bin
root,%sudo,%wheel ALL=(borg) NOPASSWD: /opt/borg/wrapper-server.sh

EOF

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

: <<LINKS

Filesystem Hierarchy Standard - http://refspecs.linuxfoundation.org/FHS_3.0/fhs-3.0.pdf
https://github.com/borgbackup/borg/blob/master/src/borg/helpers/fs.py
https://borgbackup.readthedocs.io/en/stable/usage/general.html#environment-variables
will symlink ~/.{config,cache} to the correct place so environment variables are not required

--

https://gist.github.com/steinwaywhw/a4cd19cda655b8249d908261a62687f8

https://jqplay.org/
https://stedolan.github.io/jq/manual/
https://stackoverflow.com/questions/18592173/select-objects-based-on-value-of-variable-in-object-using-jq
https://stackoverflow.com/questions/43259563/how-to-check-if-element-exists-in-array-with-jq
https://github.com/stedolan/jq/issues/106

https://stackoverflow.com/questions/9120512/verify-gpg-signature-without-installing-key

https://stackoverflow.com/questions/43158140/way-to-create-multiline-comments-in-bash

--

https://linux.die.net/man/8/sudo
https://linux.die.net/man/5/sudoers
https://www.sudo.ws/man/sudo.man.html
https://www.sudo.ws/man/sudoers.man.html
https://www.garron.me/en/linux/visudo-command-sudoers-file-sudo-default-editor.html
https://superuser.com/questions/169278/localhost-in-sudoers = useless
https://unix.stackexchange.com/questions/71684/the-host-variable-in-etc-sudoers = useless
https://serverfault.com/questions/90166/defining-hosts-in-sudoers-file
https://serverfault.com/questions/480136/how-do-i-set-both-nopasswd-and-setenv-on-the-same-line-in-sudoers
https://unix.stackexchange.com/questions/13240/etc-sudoers-specify-env-keep-for-one-command-only
https://wiki.archlinux.org/index.php/sudo
https://github.com/borgbackup/borg/blob/master/src/borg/helpers/fs.py
-> BORG_BASE_DIR
https://www.systutorials.com/docs/linux/man/8-sudo/

user host = (runas) tags: cmd

LINKS
