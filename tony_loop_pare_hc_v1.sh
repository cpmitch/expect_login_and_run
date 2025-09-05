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
# 2Dec2024:
# Make this comaptible with what Tony filters on in Excel
# Tony filters???
# Yes, Tony while working 2nd shift, generates a list of RU IP addresses based upon
# a filtering of the downloaded DISH healthcheck, usually the 4PM CT file. What he does
# is filter out a bunch of stuff, so that the resulting list is about 400 RUs with
# certain active alarms. Tony currently filters on column Z in excel, but Pete has
# replicated this with awk and filter statements in this script. This potentially
# improves Tony's manual work, decreasing time spent, increasing reliability.
# We shall see if this is adopted by Tony or others.
#
# Tony's RUINFO EXE runs against the list of 400 IP addresses and generates file:
#   ALL_ALARM_HC_NATIONWIDE_12032024_4PM_SUMMARY_RUINFO.xlsx
#
# Note: Currently this script runs on a Windows PC in CYGWIN, do not port to linux!
#
# 5Sep2025: Ported from CYGWIN to WSL by Pete after massive data loss a few days ago.
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
      allCombined="tony_all_combined_"
      # filename=$(basename $arg2)
      # filenamePrefix=$(echo $filename | cut -d '.' -f 1)
      filenameEnding=$(basename $csvFileName | cut -b 10-)

      ### Below line works, but not for the new tony script.
      ### '$9~/TX Power status change|RX out of order|Internal PS alarm|Unit out of order|Node Voltage out-of-range condition/{print}'|\
      ### awk -F, '{ print $3 "," $2 "," $5 "," $6 "," $12 "," int($13) "," $16 "," $19 "," $26 "," $8 "," int($29) "," }' $csvFileName | awk -F, '$9~/AISG PS alarm|Fronthaul Port Status change|TX Power status change|RX out of order|Internal PS alarm|Unit out of order|Sync status changes|Unit out of order|VSWR alarm/{print}' | while read line; do echo ${line}$csvFileName; done  | sort -u > $allCombined$filenameEnding

      ### Below works(at least the number 383 agrees with Tony's Excel filtering of ru_final_3Dec2024_16H.csv)
      awk -F, -vOFS=, '{ print $3 "," $2 "," $5 "," $6 "," $12 "," int($13) "," $16 "," $19 "," $26 "," $8 "," int($29) "," }' $csvFileName \
      | awk -F, '$9~/AISG PS alarm|TX Power status change|RX out of order|Internal PS alarm|Unit out of order|Unit out of order|VSWR alarm/{print}' \
      | while read line; do echo ${line}$csvFileName; done  | sort -u > $allCombined$filenameEnding

      ### Below, play around with just one output field.
      ### awk -F, -vOFS=, '{ print $26 }' $csvFileName \
      ### | awk -F, '$1~/AISG PS alarm|TX Power status change|RX out of order|Internal PS alarm|Unit out of order|Unit out of order|VSWR alarm/{print}' \
      ### | while read line; do echo ${line}$csvFileName; done > $allCombined$filenameEnding

      echo "...Added $(wc -l $allCombined$filenameEnding | awk '{ print $1 }') lines"
      # mv $csvFileName ./old_csv/
      # cp  $allCombined$filenameEnding /cygdrive/c/Users/mitchepe/Downloads/
      echo "done"
      exit 0
   fi # Exists ru_final_*.csv in current directory
   echo -n "."
   sleep 5
done
echo "File ./stop detected so stopping."
exit 0
