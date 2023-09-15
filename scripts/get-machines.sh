#/bin/bash
STATUS=""
FORMAT=""

while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
        -s|--status)
        STATUS="$2"
        shift # move past argument
        shift # move past value
        ;;
        -f|--format)
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


if [ "$FORMAT" = "csv" ]; then
      prlctl list -a | awk -v my_status="$STATUS" '$2 ~ my_status { $1=$2=$3=""; gsub(/^ */, ""); print }' | tr '\n' ',' | sed 's/,$//'
else
  prlctl list -a | awk -v my_status="$STATUS" '$2 ~ my_status { $1=$2=$3=""; gsub(/^ */, ""); print }'
fi


exit 0
