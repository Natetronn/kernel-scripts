#!/bin/bash
set -e; set -o pipefail

# Determines whether the specified (or current if no arg) directory is a kernel
# source directory.
# $1: Directory to check (defaults to current dir.)
function is_linux_dir()
{
	local path=${1:-.}

	# Something of a hack but should be effective.
	[[ -d $path/"arch" ]] && [[ -f $path/MAINTAINERS ]] && \
		[[ -f $path/"Kbuild" ]]
}

# Displays parameteters with command name prepended, outputted to stderr.
# $@: message to display.
function error()
{
	echo $(basename $0): $@ >&2
}

# Displays parameteters with command name prepended, outputted to stderr, then
# exits with error status.
# $@: message to display.
function fatal()
{
	error $@
	exit 1
}

# Pushes directory onto pushd stack without outputting anything.
# $1: Directory to add to pushd stack.
function push()
{
	pushd $1 >/dev/null
}

# Pops directory off pushd stack without outputting anything.
function pop()
{
	popd &>/dev/null || true
}

# Pushes into linux dev directory (at $LINUX_DEV_PATH), assumes this variable is
# available.
function push_linux()
{
	if is_linux_dir; then
		path="."
	else
		path="$LINUX_DEV_PATH"
	fi

	push $path
}

# Pushes into kernel dev directory (at $KERNDEV_PATH), assumes this variable is
# available.
function push_kerndev()
{
	push $KERNDEV_PATH
}

# Replaces the current script with an elevated version of itself.
# If parameters need to be preserved, they need to be passed thorough via $@.
function elevate()
{
	if [[ $EUID != 0 ]]; then
		exec sudo -E $0 $@
		exit $?
	fi
}

# Checks whether the specified binaries are available on the $PATH.
# $@: Binaries to check.
function check_exists()
{
	for file in $@; do
		(which $file &>/dev/null) || \
			fatal "Can't find required binary '$file' on path."
	done
}

# Loop mount image file into /mnt.
# $1: Image file to mount, in $KERNDEV_PATH.
function mount_image()
{
	mount -o loop $KERNDEV_PATH/$1 /mnt
}

# Attempt to unmount /mnt, ignore any failures.
function unmount()
{
	# This _can_ be dangerous, theoretically, but this is usually shortly
	# followed by an attempt at a mount, which if the unmount fails, will
	# also fail and end the script with an error.
	umount /mnt &>/dev/null || true
}

# Give ownership of the specified directory to the user (assumes $SUDO_USER is
# available!)
# $1: Directory to 'give back' to user $SUDO_USER.
function give_back()
{
	[[ -z "$SUDO_USER" ]] && error "give_back: SUDO_USER not defined." || \
		chown -R $SUDO_USER:$SUDO_USER $1
}

# Run make with specified arguments and $make_opts. If $VERBOSE is set, output
# to controlling terminal, otherwise redirect to /dev/null.
# $@: make arguments.
function mak()
{
	[[ -z $VERBOSE ]] && out="null" || out="tty"

	make $make_opts $@ >/dev/$out
}

# Determines if the argument is an command-line option.
# $1: Argument.
function is_opt()
{
	[[ $1 == -* ]]
}

# Say we're done, if we're not configured to not do so.
function say_done()
{
	[[ -z "$NO_DONE" ]] && echo Done! || true
}


# Configure kernel setting to $1 for settings in $@...
function config()
{
	choice=$1
	shift

	for setting in $@; do
		scripts/config --$choice $setting
	done
}

# Enable kernal settings $@...
function kenable()
{
	config enable $@
}

# Disable kernal settings $@...
function kdisable()
{
	config disable $@
}

# Outputs the current script directory.
function script_dir()
{
	# Source: http://stackoverflow.com/a/246128/6380063
	echo "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
}

# Check whether $LINUX_DEV_PATH is sane.
function check_linux_dev_path()
{
	[[ -d $LINUX_DEV_PATH ]] || fatal "Couldn't find kernel at $LINUX_DEV_PATH."

	is_linux_dir $LINUX_DEV_PATH || \
		fatal "Doesn't look like a linux dev path: $LINUX_DEV_PATH"
}

# Finds the base linux kernel path of the specified directory contained within a
# kernel directory structure, or if it can't be found just returns the path.
function find_base_linux_path()
{
	local path=$1
	push $path || fatal "Invalid path $path?!"

	while [[ $PWD != "/" ]] && ! is_linux_dir $PWD; do
		cd ..
	done

	if [[ $PWD == "/" ]]; then
		echo $path
	else
		echo $PWD
	fi

	pop
}
