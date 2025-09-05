#!/bin/bash
#
# Version 0 by cpmitch 26Jul2024
# Script to save only rows of dish health check that match the alarm
# criteria of column Z:
# PS alarm, Unit Out of Order, TX Power STatus Change, RX Out of Order, etc.
#
# 27Jul2024:
# More improvements
#
# 5Nov2024 Election Day:
# Make this a loop-and-wait script with support for stop marker detection
#
# 5Sep2025:
# Recovered version from CYGWIN environment after catastrophic data loss few days ago.
#
while [ ! -e ./stop ] ; do
   csvFileName=$(ls -altr ru_final_*.csv | awk '{ print $9 }' | head -n 1)
   # if [ -e ./ru_final_*.csv ] ; then
   if [ "$csvFileName" != "" ] ; then
      echo -n "Found a CSV file for processing..."
      csvFileName=$(ls -altr ru_final_*.csv | awk '{ print $9 }' | head -n 1)
      echo -n $csvFileName

      fileSize1=1
      fileSize2=2
      until [ $fileSize1 -eq $fileSize2 ] ; do
         fileSize1=$( ls -altr $csvFileName | awk '{ print $5 }')
         # echo -n " compare."
         echo -n " ."
         sleep 3
      fileSize2=$( ls -altr $csvFileName | awk '{ print $5 }')
      done
      csvFileNameOrigNumberOfLines=$(wc -l $csvFileName | awk '{ print $1 }')
      echo " $csvFileNameOrigNumberOfLines lines "

      reducedDotcsv="_reduced.csv"
      allCombined="all_combined_"
      # filename=$(basename $arg2)
      # filenamePrefix=$(echo $filename | cut -d '.' -f 1)
      filenameEnding=$(basename $csvFileName | cut -b 10-)

      awk -F, '{ print $3 "," $2 "," $5 "," $6 "," $12 "," int($13) "," $16 "," $19 "," $26 "," $8 "," int($29) "," }' $csvFileName | awk -F, '$9~/TX Power status change|RX out of order|Internal PS alarm|Unit out of order|Node Voltage out-of-range condition/{print}' | while read line; do echo ${line}$csvFileName; done  | sort -u > $allCombined$filenameEnding

      echo "...Added $(wc -l $allCombined$filenameEnding | awk '{ print $1 }') lines"
      mv $csvFileName ./old_csv/
      # cp  $allCombined$filenameEnding /cygdrive/c/Users/mitchepe/Downloads/
      echo "done"
      # exit 0
   fi # Exists ru_final_*.csv in current directory
   echo -n "."
   sleep 5
done
echo "File ./stop detected so stopping."
exit 0
