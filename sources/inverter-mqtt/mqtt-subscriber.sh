#!/bin/bash

INFLUX_ENABLED=`cat /etc/inverter/mqtt.json | jq '.influx.enabled' -r`
pushMQTTData () {
    MQTT_SERVER=`cat /etc/inverter/mqtt.json | jq '.server' -r`
    MQTT_PORT=`cat /etc/inverter/mqtt.json | jq '.port' -r`
    MQTT_TOPIC=`cat /etc/inverter/mqtt.json | jq '.topic' -r`
    MQTT_DEVICENAME=`cat /etc/inverter/mqtt.json | jq '.devicename' -r`
    MQTT_USERNAME=`cat /etc/inverter/mqtt.json | jq '.username' -r`
    MQTT_PASSWORD=`cat /etc/inverter/mqtt.json | jq '.password' -r`

    mosquitto_pub \
        -h $MQTT_SERVER \
        -p $MQTT_PORT \
        -u "$MQTT_USERNAME" \
        -P "$MQTT_PASSWORD" \
        -t "$MQTT_TOPIC/sensor/"$MQTT_DEVICENAME"_$1" \
        -m "$2"
    
    if [[ $INFLUX_ENABLED == "true" ]] ; then
        pushInfluxData $1 $2
    fi
}

pushInfluxData () {
    INFLUX_HOST=`cat /etc/inverter/mqtt.json | jq '.influx.host' -r`
    INFLUX_USERNAME=`cat /etc/inverter/mqtt.json | jq '.influx.username' -r`
    INFLUX_PASSWORD=`cat /etc/inverter/mqtt.json | jq '.influx.password' -r`
    INFLUX_DEVICE=`cat /etc/inverter/mqtt.json | jq '.influx.device' -r`
    INFLUX_PREFIX=`cat /etc/inverter/mqtt.json | jq '.influx.prefix' -r`
    INFLUX_DATABASE=`cat /etc/inverter/mqtt.json | jq '.influx.database' -r`
    INFLUX_MEASUREMENT_NAME=`cat /etc/inverter/mqtt.json | jq '.influx.namingMap.'$1'' -r`
    
    curl -i -XPOST "$INFLUX_HOST/write?db=$INFLUX_DATABASE&precision=s" -u "$INFLUX_USERNAME:$INFLUX_PASSWORD" --data-binary "$INFLUX_PREFIX,device=$INFLUX_DEVICE $INFLUX_MEASUREMENT_NAME=$2"
}

while read rawcmd;
do

    echo "Incoming request send: [$rawcmd] to inverter."
    echo "Incoming request send: Waiting for Serial Port"
    for VARIABLE in 1 2 3 4 5 N
    do
        APP_PID_SUB=`ps -ef | grep [s]ocat  | awk '{ print $2 }' | awk -v def="default" '{print} END { if(NR==0) {print 123123123} }'`
        timeout 10 tail --pid=$APP_PID_SUB -f /dev/null
        APP_PID_SUB=`ps -ef | grep [s]ocat  | awk '{ print $2 }' | awk -v def="default" '{print} END { if(NR==0) {print 123123123} }'`
        timeout 10 tail --pid=$APP_PID_SUB -f /dev/null
        echo "Incoming request send: Serial Port Available"
        socat pty,link=/dev/ttyS6,b2400,cstopb=0,csize=cs8,raw,echo=0 tcp:192.168.0.73:23 & export APP_PID=$!
        INVERTER_DATA=`timeout 10 /opt/inverter-cli/bin/inverter_poller -r $rawcmd`
        echo "INVERTER_DATA: $INVERTER_DATA"
        Reply=`echo $INVERTER_DATA | cut -d':' -f2 | sed -e 's/^[[:space:]]*//'`
        echo "Reply: $Reply"
        [ ! -z "$Reply" ] && pushMQTTData "Reply" "$Reply ($rawcmd)"
        kill $APP_PID
        if [ -n "${Reply}" ]; then
            break
        fi
    done


done < <(mosquitto_sub -h $MQTT_SERVER -p $MQTT_PORT -u "$MQTT_USERNAME" -P "$MQTT_PASSWORD" -t "$MQTT_TOPIC/sensor/$MQTT_DEVICENAME" -q 1)
