#!/usr/bin/env bash

# shellcheck source=/dev/null

# Colours
R="\e[1;31m"
G="\e[1;32m"
Y="\e[1;33m"
RT="\e[0m"

# Functions for printing
good() {
	echo -e "[${G}*${RT}] $*"
}

bad() {
	echo -e "[${R}!${RT}] $*" >&2
}

# Usage
usage() {
	echo -e "Usage: $0 ${G}[options..]${RT} <Arg>
${G}-h${RT} <host> - Specify host (example: https://bin.cyberknight777.dev, https://bin.mangeshrex.me) (default: https://bin.perosar.tech)
${G}-e${RT} <time> - Set expire time (example: 1h)
${G}-d${RT} <PasteID> - Delete a paste (example: aBcD)
${G}-f${RT} <filename> - Paste a file (example: hello.txt)
${G}-s${RT} <URL> - Shorten a URL (example: https://google.com)" >&2
	exit 1
}

# Parse command-line arguments
while getopts ":h:f:s:e:d:c" arg; do
	case "${arg}" in
	"h")
		HOST="${OPTARG}"
		;;
	"f")
		FILES+=("${OPTARG}")
		;;
	"s")
		SHORTS+=("${OPTARG}")
		;;
	"d")
		DELETES+=("${OPTARG}")
		;;
	"e")
		EXPIRE_TIME="${OPTARG}"
		;;
	"c")
		read -r -p "Enter host: " HOST
		read -r -p "Do you want to copy paste URLs? (y/n): " CLIP
		read -r -p "Enter your clipboard command (leave empty for default): " CLIP_CMD

		case "$CLIP" in
		"y" | "Y")
			CLIP="true"
			;;
		"n" | "N")
			CLIP="false"
			;;
		esac

		if [[ ! -f ./rbinrc.template ]]; then
			bad "Config can only be generated inside cloned repository"
			exit 1
		fi

		sed ./rbinrc.template \
			-e "s|@HOST@|$HOST|g" \
			-e "s|@CLIP@|$CLIP|g" \
			-e "s|@CLIP_CMD@|$CLIP_CMD|g" >~/.rbinrc

		good "Generated config"

		exit 0
		;;
	*)
		usage
		;;
	esac
done

shift "$((OPTIND - 1))"

# Default values for variables
: "${HOST:=https://bin.perosar.tech}"
FORM_FIELD="highlight"
. ~/.rbinrc 2>/dev/null

# Ensure atleast one action is specified
if [[ -z "${FILES[*]}" && -z "${SHORTS[*]}" && -z "${DELETES[*]}" ]]; then
	bad "Please specify ATLEAST one file to paste / delete or URL to shorten!"
	usage
fi

# Copy-to-clipboard function
clip() {
	if $CLIP_COPY; then
		if [[ -n "$CLIP_CMD" ]]; then
			$CLIP_CMD <<<"$1"
			exit 0
		fi

		if [[ -n "$(command -v termux-clipboard-set)" ]]; then
			# use timeout in case termux-api is installed but the termux:api app is missing
			# taken from termux-info
			timeout 3 termux-clipboard-set <<<"$1"
			timeout 3 termux-toast "Copied to clipboard"
		elif [[ -n "$(command -v xclip)" ]]; then
			xclip -selection c <<<"$1"
		fi
	fi
}

# Make request with form data
mkreq_form() {
	# Send `Expire` header if specified
	if [[ -z "$EXPIRE_TIME" ]]; then
		curl --silent --form "$1"="$2" "$HOST"
	else
		curl --silent --header "Expire: ${EXPIRE_TIME}" --form "$1"="$2" "$HOST"
	fi
}

# Make delete request
mkreq_del() {
	curl --silent --request DELETE "${HOST}/${1}"
}

paste_all() {
	if [[ -n "${FILES[*]}" ]]; then
		good "Pasting specified files"
	fi

	local START=0
	local TOTAL="${#FILES[@]}"

	for file in "${FILES[@]}"; do

		local EXT
		case "$file" in
		*"."*)
			EXT=".${file##*.}"
			;;
		esac

		# Handle errors if file doesn't exist
		if [[ ! -f "$file" ]]; then
			bad "File '$file' doesn't exist!"
			continue
		fi

		((START++))
		echo -en "[${Y}${START}${RT}/${G}${TOTAL}${RT}] Pasting $file... "

		local o
		o=$(mkreq_form "$FORM_FIELD" "@${file}")
		echo "Pasted to $o${EXT}"
		clip "$o"

	done
}

short_all() {
	if [[ -n "${SHORTS[*]}" ]]; then
		good "Shortening specified URLs"
	fi

	local START=0
	local TOTAL="${#SHORTS[@]}"

	for short in "${SHORTS[@]}"; do
		local FORM_FIELD="short"

		((START++))
		echo -en "[${Y}${START}${RT}/${G}${TOTAL}${RT}] Shortening $short... "

		local o
		o=$(mkreq_form "$FORM_FIELD" "$short")
		echo "Shortened to $o"
		clip "$o"
	done
}

delete_all() {
	if [[ -n "${DELETES[*]}" ]]; then
		good "Deleting specified pastes"
	fi

	local START=0
	local TOTAL="${#DELETES[@]}"

	for paste in "${DELETES[@]}"; do
		((START++))
		echo -en "[${Y}${START}${RT}/${G}${TOTAL}${RT}] Deleting $paste... "

		local o
		o=$(mkreq_del "$paste")

		case "$o" in
		*"deleted"*)
			echo "Deleted $paste"
			;;
		*"failed"*)
			echo "No paste with ID $paste"
			;;
		*)
			echo "Unknown error"
			;;
		esac
	done
}

paste_all
short_all
delete_all
