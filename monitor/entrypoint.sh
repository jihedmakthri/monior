#!/bin/sh
export INFLUX_TOKEN=$(cat /run/secrets/telegraf-token)
export VC_URL=$(cat /run/secrets/vcenter-url)
export VC_USR_RO=$(cat /run/secrets/vcenter-user-ro)
export VC_PRO=$(cat /run/secrets/vcenter-user-pro)
# Optional: echo for debug (remove in production)

echo "INFLUX_TOKEN loaded: $INFLUX_TOKEN"
echo "VC_URL loaded: $VC_URL"
echo "VC_USR_RO loaded: $VC_USR_RO"
echo "VC_PRO loaded: **********************************"
# Now launch Telegraf
exec telegraf
