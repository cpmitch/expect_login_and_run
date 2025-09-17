#!/bin/bash
sleep_number=1
until [ ! -e ./pause ] ; do
   sleep $sleep_number
   echo -n "."
   sleep_number=$((RANDOM % 13 + 45))
done
echo "./pause gone, exiting..."
