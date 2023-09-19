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
  -f | --format)
    FORMAT="$2"
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
lines=""

for user in $(get_host_users); do
  line=""
  [ -n "${user}" ] && [ -e "/Users/${user}" ] || continue
  if [ "$FORMAT" = "csv" ]; then
    line=$(sudo -u $user prlctl list -a | awk -v my_status="$STATUS" '$2 ~ my_status { $1=$2=$3=""; gsub(/^ */, ""); print }' | tr '\n' ',' | sed 's/,$//' | sed 's/NAME//')
  else
    line=$(sudo -u $user prlctl list -a | awk -v my_status="$STATUS" '$2 ~ my_status { $1=$2=$3=""; gsub(/^ */, ""); print }' | tr '\n' '|' | sed 's/|$//' | sed 's/NAME|//')
  fi
  #echo $line
  if [ -n "$line" ]; then
    if [ -n "$lines" ]; then
      lines="$lines | $line"
    else
      lines="$line"
    fi
  fi
done

lines=${lines//|/ | }

echo "<result>$lines</result>"