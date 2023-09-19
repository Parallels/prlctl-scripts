get_host_users() {
	dscl . list /Users | grep -v "^_" | grep '\S'
}
user_count=0

for user in $(get_host_users); do
  [ -n "${user}" ] && [ -e "/Users/${user}" ] || continue
  count=$(sudo -u $user prlctl list -a | grep -oE '\{[a-f0-9\-]+\}' | wc -l | awk '{$1=$1};1')
  user_count=$((user_count + count))
done
echo "Total number of VMs for all users: $user_count"


