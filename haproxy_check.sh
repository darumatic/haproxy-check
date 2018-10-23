#!/bin/bash -e

#CONF                           the haproxy configuration file path i.g. /etc/haproxy/haproxy.cfg
#DOMAIN_TEST                    domain name to test backends with
#TTFB_TEST                      max time-to-first-byte value
#LOG_FILE                       the log file path
#TEST_BACKENDS                  The array of target backend, e.g. TEST_BACKENDS=("web" "websocket")
#TEST_PORTS                     The array of test port of target backend, e.g. TEST_PORTS=("80" "8080")

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

if ! which nc &>/dev/null
then echo "install nc , e.g. yum install nc" ; exit
fi

if ! which ts &>/dev/null
then echo "install moreutils , e.g. yum install moreutils" ; exit
fi

echo_to_file(){
    echo $1 | ts | tee -a $LOG_FILE
}

disable_backend_server() {
local SERVER=$1
echo_to_file "==disabling backend $BACKEND_NAME/$SERVER"
echo "disable server $BACKEND_NAME/$SERVER"      | nc -U /var/lib/haproxy/stats
}

enable_backend_server() {
local SERVER=$1
echo_to_file "==enabling backend $BACKEND_NAME/$SERVER"
echo "enable server $BACKEND_NAME/$SERVER"      | nc -U /var/lib/haproxy/stats
}

list_enabled_backend_servers() {
echo "show stat" | nc -U /var/lib/haproxy/stats | \
    awk -F, '{if ($1 == "'$BACKEND_NAME'" && $2 != "BACKEND" && $18 == "UP") print $2 }' | sort -u
}

list_disabled_backend_servers() {
echo "show stat" | nc -U /var/lib/haproxy/stats | \
    awk -F, '{if ($1 == "'$BACKEND_NAME'" && $2 != "BACKEND" && $18 == "MAINT") print $2 }' | sort -u
}

get_server_ip() {
local SERVER=$1
cat $CONF| grep -oP 'server\s+'$SERVER'\s+[a-zA-Z0-9\-\.]*'  | awk '{print $3}' | sort -u | head -n 1
}

get_ttfb() {
local TTFB=$( curl  http://$SERVER_IP:$BACKEND_PORT --header "Host: $DOMAIN"  -w "%{time_starttransfer}" -Ss -o /dev/null )
echo $TTFB
}

test_backend(){

    local BACKEND_NAME=$1
    local BACKEND_PORT=$2

    echo
    echo "===testing disabled servers of backend $BACKEND_NAME"
    for SERVER in `list_disabled_backend_servers`
    do
        SERVER_IP=$( get_server_ip $SERVER)
        DOMAIN=$DOMAIN_TEST
        echo
        echo "= testing $SERVER / $SERVER_IP:$BACKEND_PORT "
        TTFB=$( get_ttfb )
        echo "= got TTFB $TTFB"
        if perl -e ' exit  ( '$TTFB' < '$TTFB_TEST' ? 0 : 1 )  '
        then    enable_backend_server $SERVER
        else    echo "= do nothing"
        fi
    done

    echo

    echo "===testing enabled servers of backend $BACKEND_NAME"
    for SERVER in `list_enabled_backend_servers`
    do
        SERVER_IP=$( get_server_ip $SERVER)
        DOMAIN=$DOMAIN_TEST
        echo
        echo "= testing $SERVER / $SERVER_IP:$BACKEND_PORT "
        TTFB=$( get_ttfb )
        echo "= got TTFB $TTFB"
        if perl -e ' exit  ( '$TTFB' >  '$TTFB_TEST' ? 0 : 1 )  '
        then    disable_backend_server $SERVER
        else    echo "= do nothing"
        fi
    done

    if [ $( list_enabled_backend_servers | wc -l ) == 0 ]
    then
    #enable random disabled server
    enable_backend_server $( list_disabled_backend_servers | sort -R | head -n1 )
    fi
}

for i in ${!TEST_BACKENDS[@]};
do
  TEST_BACKEND=${TEST_BACKENDS[$i]}
  TEST_PORT=${TEST_PORTS[$i]}
  test_backend $TEST_BACKEND $TEST_PORT
done


