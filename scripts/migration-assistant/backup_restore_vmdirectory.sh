#!/bin/bash
#
# backup_restore_vmdirectory.sh
#
# PURPOSE
#   Backs up and restores two Parallels Desktop preference files that define
#   which virtual machines are registered on the system:
#     - dispatcher.desktop.xml  (Parallels service / user registration)
#     - vmdirectorylist.desktop.xml  (VM inventory / paths)
#
#   BACKUP  Copies both files from /Library/Preferences/Parallels to
#           /Users/Shared/Parallels with open permissions (0777 on the
#           directory, 0644 root:wheel on each file) so they are readable
#           by any subsequent user or MDM agent.
#
#   RESTORE Copies the backed-up files back to /Library/Preferences/Parallels
#           on a new or migrated Mac — but ONLY when the destination files do
#           not already exist (i.e. a fresh Parallels install). To avoid UUID
#           collisions after Migration Assistant cloning, all VmGlobalUuid and
#           ParallelsUser Uuid values are regenerated during restore.
#
# TYPICAL USE CASES
#   - Recurring scheduled backup (e.g., daily Jamf policy) to capture newly
#     added VMs.
#   - Login-event restore after Migration Assistant to re-register VMs with
#     Parallels Desktop without manual user action.
#
# PROVIDED AS-IS
#   This script is provided as-is, without warranty of any kind. Test
#   thoroughly in your environment before deploying to production. Parallels
#   is not responsible for data loss resulting from incorrect or unsupported
#   use of this script.
#
# ENVIRONMENT OVERRIDES (optional)
#   SHARED_DIR   Backup destination  (default: /Users/Shared/Parallels)
#   PREFS_DIR    Parallels prefs dir (default: /Library/Preferences/Parallels)
#   SRC_DIR      Backup source       (default: /Library/Preferences/Parallels)
#   DST_DIR      Backup destination  (default: /Users/Shared/Parallels)
#

set -euo pipefail

DISPATCHER_FILE_NAME="dispatcher.desktop.xml"
VMDIR_FILE_NAME="vmdirectorylist.desktop.xml"

SHARED_DIR="${SHARED_DIR:-/Users/Shared/Parallels}"

PREFS_DIR="${PREFS_DIR:-/Library/Preferences/Parallels}"

##################################

backup_pd_files() {
	SRC_DIR="${SRC_DIR:-/Library/Preferences/Parallels}"
	DST_DIR="${DST_DIR:-/Users/Shared/Parallels}"

	FILES=(
		"${DISPATCHER_FILE_NAME}"
		"${VMDIR_FILE_NAME}"
	)

	for file in "${FILES[@]}"; do
		src_path="${SRC_DIR}/${file}"
		dst_path="${DST_DIR}/${file}"

		if [ ! -f "${src_path}" ]; then
			continue
		fi

		mkdir "${DST_DIR}" || true
		chmod 0777 "${DST_DIR}" || true

		cp -fp "${src_path}" "${dst_path}"
		chmod 0644 "${dst_path}"
		chown root:wheel "${dst_path}"
	done
}

new_uuid() {
	echo "{$(uuidgen | tr "[:upper:]" "[:lower:]")}"
}

replace_vmglobaluuids() {
	local path=$1
	local content
	local output=""
	local text
	local tag
	local replace_value=0

	content=$(<"${path}")

	while [[ ${content} =~ ^([^<]*)(<[^>]+>)(.*)$ ]]; do
		text=${BASH_REMATCH[1]}
		tag=${BASH_REMATCH[2]}
		content=${BASH_REMATCH[3]}

		if (( replace_value )); then
			if [ "${tag}" = "</VmGlobalUuid>" ]; then
				output+=$(new_uuid)
				output+="${tag}"
				replace_value=0
				continue
			fi
		fi

		output+="${text}${tag}"

		if [ "${tag}" = "<VmGlobalUuid>" ]; then
			replace_value=1
		fi
	done

	printf '%s' "${output}${content}" > "${path}"
}

replace_parallels_user_uuids() {
	local path=$1
	local content
	local output=""
	local text
	local tag
	local in_parallels_user=0
	local depth=0
	local replace_value=0

	content=$(<"${path}")

	while [[ ${content} =~ ^([^<]*)(<[^>]+>)(.*)$ ]]; do
		text=${BASH_REMATCH[1]}
		tag=${BASH_REMATCH[2]}
		content=${BASH_REMATCH[3]}

		if (( replace_value )); then
			if [ "${tag}" = "</Uuid>" ]; then
				output+=$(new_uuid)
				output+="${tag}"
				replace_value=0
				((depth--))
				if (( depth == 0 )); then
					in_parallels_user=0
				fi
				continue
			fi
		fi

		output+="${text}${tag}"

		if (( !in_parallels_user )); then
			if [[ ${tag} == "<ParallelsUser>" ]] || [[ ${tag} == \<ParallelsUser\ *\> ]]; then
				in_parallels_user=1
				depth=1
			fi
			continue
		fi

		if [ "${tag}" = "</ParallelsUser>" ]; then
			((depth--))
			if (( depth == 0 )); then
				in_parallels_user=0
			fi
		elif [ "${tag}" = "<Uuid>" ] && (( depth == 1 )); then
			replace_value=1
			((depth++))
		elif [[ ${tag:0:2} == "<?" ]] || [[ ${tag:0:2} == "<!" ]]; then
			:
		elif [[ ${tag} == \<*\/\> ]] && [[ ${tag} != \</* ]]; then
			:
		elif [[ ${tag} == \<* ]] && [[ ${tag} != \</* ]]; then
			((depth++))
		elif [[ ${tag} == \</* ]]; then
			((depth--))
			if (( depth == 0 )); then
				in_parallels_user=0
			fi
		fi
	done

	printf '%s' "${output}${content}" > "${path}"
}

restore_pd_files() {

	DISPATCHER_FILE_SRC="${SHARED_DIR}/${DISPATCHER_FILE_NAME}"
	VMDIR_FILE_SRC="${SHARED_DIR}/${VMDIR_FILE_NAME}"

	DISPATCHER_FILE_DST="${PREFS_DIR}/${DISPATCHER_FILE_NAME}"
	VMDIR_FILE_DST="${PREFS_DIR}/${VMDIR_FILE_NAME}"

	# Check if restore required
	if [ -f "${DISPATCHER_FILE_DST}" ] || [ -f "${VMDIR_FILE_DST}" ] || [ ! -f "${DISPATCHER_FILE_SRC}" ] || [ ! -f "${VMDIR_FILE_SRC}" ]; then
		return
	fi

	mkdir "${PREFS_DIR}" || true
	chmod 0755 "${PREFS_DIR}"
	chown root:wheel "${PREFS_DIR}"

	cp -fp "${DISPATCHER_FILE_SRC}" "${DISPATCHER_FILE_DST}"
	chmod 0644 "${DISPATCHER_FILE_DST}"
	chown root:wheel "${DISPATCHER_FILE_DST}"
	replace_parallels_user_uuids "${DISPATCHER_FILE_DST}"

	cp -fp "${VMDIR_FILE_SRC}" "${VMDIR_FILE_DST}"
	chmod 0644 "${VMDIR_FILE_DST}"
	chown root:wheel "${VMDIR_FILE_DST}"
	replace_vmglobaluuids "${VMDIR_FILE_DST}"
}

# Will backup if needed
backup_pd_files

# Will restore if needed
restore_pd_files
