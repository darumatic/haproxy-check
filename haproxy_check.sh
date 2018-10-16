#!/bin/bash


#DOMAIN_TEST                    domain name to test backends with
#TTFB_TEST=5                    max time-to-first-byte value
#BACKEND_PATTERN="p-icp-\d+"    pattern to detect backend hostnames in  haproxy config file
#BACKEND_PORT=8080              http port to test backends with


PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

if ! which nc &>/dev/null
then echo "install nc , e.g. yum install nc" ; exit
fi

disable_backend_server() {
    local BACKEND=$1
    echo "==disabling backend $BACKEND"
    echo "disable server icp/$BACKEND"      | nc -U /var/lib/haproxy/stats
    echo "disable server icp-ssl/$BACKEND"  | nc -U /var/lib/haproxy/stats
}

enable_backend_server() {
    local BACKEND=$1
    echo "==enabling backend $BACKEND"
    echo "enable server icp/$BACKEND"      | nc -U /var/lib/haproxy/stats
    echo "enable server icp-ssl/$BACKEND"  | nc -U /var/lib/haproxy/stats
}

list_enabled_backend_servers() {
echo "show stat" | nc -U /var/lib/haproxy/stats | \
    grep  -P ",$BACKEND_PATTERN" | awk -F, '{if ($18 == "UP") print $2 }' | sort -u
}

list_disabled_backend_servers() {
echo "show stat" | nc -U /var/lib/haproxy/stats | \
    grep  -P ",$BACKEND_PATTERN" | awk -F, '{if ($18 == "MAINT") print $2 }' | sort -u
}

get_backend_ip() {
local BACKEND=$1
cat $CONF| grep -oP 'server\s+'$BACKEND'\s+[\d\.]+(?=:)'  | awk '{print $3}' | sort -u
}

get_ttfb() {
local TTFB=$( curl  http://$SERVER_IP:$BACKEND_PORT --header "Host: $DOMAIN"  -w "%{time_starttransfer}" -Ss -o /dev/null )
echo $TTFB
}

echo
echo "===testing disabled backends"
for BACKEND in `list_disabled_backend_servers`
do
    SERVER_IP=$( get_backend_ip $BACKEND)
    DOMAIN=$DOMAIN_TEST
    echo
    echo "= testing $BACKEND / $SERVER_IP "
    TTFB=$( get_ttfb )
    echo "= got TTFB $TTFB"
    if perl -e ' exit  ( '$TTFB' < '$TTFB_TEST' ? 0 : 1 )  '
    then    enable_backend_server $BACKEND
    else    echo "= do nothing"
    fi
done

echo
echo "===testing enabled  backends"
for BACKEND in `list_enabled_backend_servers`
do
    SERVER_IP=$( get_backend_ip $BACKEND)
    DOMAIN=$DOMAIN_TEST
    echo
    echo "= testing $BACKEND / $SERVER_IP "
    TTFB=$( get_ttfb )
    echo "= got TTFB $TTFB"
    if perl -e ' exit  ( '$TTFB' >  '$TTFB_TEST' ? 0 : 1 )  '
    then    disable_backend_server $BACKEND
    else    echo "= do nothing"
    fi
done



if [ $( list_enabled_backend_servers | wc -l ) == 0 ]
then
   #enable random disabled server
   enable_backend_server $( list_disabled_backend_servers | sort -R | head -n1 )
fi
