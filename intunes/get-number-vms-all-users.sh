get_host_users() {
  dscl . list /Users | grep -v "^_" | grep '\S'
}

# Create an empty temporary file
temp_file=$(mktemp /tmp/uuids.XXXXXX)
for user in $(get_host_users); do
  [ -n "${user}" ] && [ -e "/Users/${user}" ] || continue

  input_data=$(sudo -u $user /usr/local/bin/prlctl list -a)

  echo "$input_data" | awk '{gsub(/[{}]/, "", $1); print $1}' | while read uuid; do
    if ! grep -q "$uuid" "$temp_file"; then
      if [ "$uuid" != "UUID" ]; then
        echo "$uuid" >>"$temp_file"
      fi
    fi
  done
done

user_count=$(wc -l "$temp_file" | awk '{$1=$1};1' | cut -d' ' -f1)

rm "$temp_file"  # Cleanup the temporary file

echo "$user_count"
