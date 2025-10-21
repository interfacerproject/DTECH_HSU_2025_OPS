#!/bin/sh
# HOST=$1
# TIMEOUT=120
# INTERVAL=5

# echo Waiting for host "$HOST" to respond to ping...
# END_TIME=$((SECONDS + TIMEOUT))
# while [[ $SECONDS -lt $END_TIME ]]; do
#   if ping -c 1 -W 3 "$HOST" &>/dev/null; then
#   # if ping -c 1 -W 3 "$HOST" ; then
#     sleep 1
#     echo Host "$HOST" is reachable!
#     sleep $INTERVAL
#     exit 0
#   fi
#   echo Host "$HOST" is not reachable, waiting "$INTERVAL"s before retrying...
#   sleep $INTERVAL
# done

# echo Timed out waiting for host "$HOST" to respond to ping.
# exit 1

HOST=$1
PORT=${2:-22}  # Default HTTP port, ma puoi usare 22 per SSH, 443 per HTTPS, etc.
TIMEOUT=120
INTERVAL=5

if [ -z "$HOST" ]; then
    echo "Utilizzo: $0 <HOST> [PORT]"
    echo "Esempi:"
    echo "  $0 google.com 80    # HTTP"
    echo "  $0 google.com 443   # HTTPS"  
    echo "  $0 192.168.1.1 22   # SSH"
    exit 1
fi

echo "Waiting for host \"$HOST:$PORT\" to respond..."

START_TIME=$(date +%s)
END_TIME=$((START_TIME + TIMEOUT))

# Funzione per testare la connettività
test_connection() {
    
    # Metodo 1: netcat se disponibile
    if command -v nc >/dev/null 2>&1; then
        nc -z -w 3 "$HOST" "$PORT" 2>/dev/null
        return $?
    fi
    
    # Metodo 2: telnet come fallback
    if command -v telnet >/dev/null 2>&1; then
        timeout 3 telnet "$HOST" "$PORT" 2>&1 | grep -q "Connected"
        return $?
    fi
    
    # Metodo 3: curl se disponibile
    if command -v curl >/dev/null 2>&1; then
        curl --connect-timeout 3 --max-time 3 -s "telnet://$HOST:$PORT" >/dev/null 2>&1
        return $?
    fi
    
    # Metodo 4: wget come ultimo tentativo
    if command -v wget >/dev/null 2>&1; then
        wget --timeout=3 --tries=1 --spider "http://$HOST:$PORT" >/dev/null 2>&1
        return $?
    fi
    
    echo "ERROR: No suitable tool found (nc, telnet, curl, wget)"
    return 1
}

while [ "$(date +%s)" -lt "$END_TIME" ]; do
    printf "Trying to connect to %s:%s... " "$HOST" "$PORT"
    
    if test_connection "$HOST" "$PORT"; then
        echo "SUCCESS!"
        echo "Host \"$HOST:$PORT\" is reachable!"
        exit 0
    else
        echo "FAILED"
    fi
    
    CURRENT_TIME=$(date +%s)
    REMAINING=$((END_TIME - CURRENT_TIME))
    echo "Host \"$HOST:$PORT\" is not reachable, waiting ${INTERVAL}s before retrying... (${REMAINING}s remaining)"
    sleep $INTERVAL
done

echo "Timed out waiting for host \"$HOST:$PORT\" to respond."
exit 1