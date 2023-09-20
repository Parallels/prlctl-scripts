#/bin/bash
STATUS=""
FORMAT=""

while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
  -s | --status)
    STATUS="$2"
    shift # move past argument
    shift # move past value
    ;;
  *)
    # unknown option
    shift # move past argument
    ;;
  esac
done

get_host_users() {
  dscl . list /Users | grep -v "^_" | grep '\S'
}

# Create an empty temporary file
temp_file=$(mktemp /tmp/uuids.XXXXXX)
for user in $(get_host_users); do
  [ -n "${user}" ] && [ -e "/Users/${user}" ] || continue

  input_data=$(sudo -u $user prlctl list -a)
  filtered_data=$input_data

  if [ -n "$STATUS" ]; then
    filtered_data=$(echo "$input_data" | awk -v filter="$STATUS" '$2 == filter {gsub(/[{}]/, "", $1); print $1}')
  fi

  echo "$filtered_data" | awk '{gsub(/[{}]/, "", $1); print $1}' | while read uuid; do
    if ! grep -q "$uuid" "$temp_file"; then
      if [ "$uuid" != "UUID" ]; then
        echo "$uuid" >>"$temp_file"
      fi
    fi
  done
done

user_count=$(wc -l "$temp_file" | awk '{$1=$1};1' | cut -d' ' -f1)

rm "$temp_file"  # Cleanup the temporary file

echo "<result>$user_count</result>"
