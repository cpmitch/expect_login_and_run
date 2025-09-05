!/bin/bash
#
# Version 0 by cpmitch 26Jul2024
# Script to save only rows of dish health check that match the alarm
# criteria of column Z:
# PS alarm, Unit Out of Order, TX Power STatus Change, RX Out of Order, etc.
# Usage:
# ./script.sh ru_final_1Jan2025_8H.csv
#
# 27Jul2024:
# More improvements
#
# 5Nov2024 Election Day:
# Make this a loop-and-wait script with support for stop marker detection
#
# 22Nov2024:
# Modify to save much more data to be used in the new Pete-DB schema. 
#
# 25Nov2024:
# Modify to work on Pete's linux box hosting the DB
#
# 27Nov2024:
# Add wait hooks to keep from processing the file if it hasn't been fully written to disk.
#
# 29Nov2024:
# The SQL timedate structure is: 2024-11-29 11:30:46
# Notice it DOES NOT have a "t" in there, so modify the scipt to put a space.
#
# 3Dec2024:
# Added option to delete the original ru_final_ file.
#
# 4Dec2024:
# Logging simplification, added duration time.
#
# 5Dec2024:
# Added start, duration, end and RUs polled per second.
#
# 6Dec2024:
# Added support for ./once marker so you run once, then exit.
#
# 7Dec2024:
# Counting column 10 Reachable, etc, printing results as a percent of total
# 
# 16Dec2024:
# Attempting to optimize(speedup) the huge sprawling awk statement. Wish me luck.
#
# 17Dec2024:
# Now remove all of the filler such as ",  " and "  ," from the file with a few sed statements.
#
# 19Dec2024:
# New test for file exists means we can cleanly print dots to the screen as we wait for the next
# file to show up.
#
# 12Feb2025:
# Moving development to Fujitsu laptop Ubuntu environment which forks things, right?
#
# 14Apr2025:
# Removing all of the -NC- and NA entries. Makes the output file even smaller.
#
ELAPSEDSECONDS=0

getSTARTDATE (){
   STARTDATE1="2014-10-18 22:16:30"
   STARTDATE2="2014-10-18 22:16:31"
   until [ "$STARTDATE1" == "$STARTDATE2" ] ; do
      STARTDATE1="$(date '+%Y')-$(date '+%m')-$(date '+%d') $(date '+%H'):$(date '+%M'):$(date '+%S')"
      sleep 0.100000
      STARTDATE2="$(date '+%Y')-$(date '+%m')-$(date '+%d') $(date '+%H'):$(date '+%M'):$(date '+%S')"
   done
   STARTDATE=$STARTDATE1
}

getENDDATE (){
   ENDDATE1="2014-10-18 22:16:30"
   ENDDATE2="2014-10-18 22:16:31"
   until [ "$ENDDATE1" == "$ENDDATE2" ] ; do
      ENDDATE1="$(date '+%Y')-$(date '+%m')-$(date '+%d') $(date '+%H'):$(date '+%M'):$(date '+%S')"
      sleep 0.100000
      ENDDATE2="$(date '+%Y')-$(date '+%m')-$(date '+%d') $(date '+%H'):$(date '+%M'):$(date '+%S')"
   done
   ENDDATE=$ENDDATE1
}

if [ ! -e ./old_csv ] ; then
   echo "Please mkdir ./old_csv first, ending."
   exit 139
fi

csvNormalNumberOfHeaderColumns=163
csvNumberOfNormalFirstLineColumns=163

while [ ! -e ./stop ] ; do
   files=(ru_final_*H.csv)
   if [ -e "${files[0]}" ] ; then
   csvFileName=$(ls -altr ru_final_*H.csv | awk '{ print $9 }' | head -n 1)
   # files=(ru_final_*H.csv)
   ### if compgen -G ./ru_final_*.csv > /dev/null; then
      ### Files found in hte current directory, so process them!
      getSTARTDATE
      echo ""
      echo -n "Found "
      ### csvFileName=$(ls -altr ru_final_*.csv | awk '{ print $9 }' | head -n 1)
      csvFileName=$files
      echo -n $csvFileName
      echo -n " "

      ### Step 0) Loop and wait until the imput file size becomes static.
      ###         A crude way to determine the files has been written to
      ###         completely so that we do not process the partial file
      ###         while it's being written as during SFTP transfer.
      ###
      fileSize1=1
      fileSize2=2
      until [ $fileSize1 -eq $fileSize2 ] ; do
         fileSize1=$( ls -altr $csvFileName | awk '{ print $5 }')
         # echo -n " compare."
         echo -n "|"
         sleep 3
      fileSize2=$( ls -altr $csvFileName | awk '{ print $5 }')
      done
      ### Step 0.a Check the file has correct number of columns of data, as of 14Apr2025 that number is 163
      ###
      csvFileNameOrigNumberOfLines=$(wc -l $csvFileName | awk '{ print $1 }')
      echo -n " $csvFileNameOrigNumberOfLines lines, "
      csvNumberOfHeaderColumns=$(head -n 1 $csvFileName | awk -F, '{ print NF }')
      if [ "$csvNumberOfHeaderColumns" != "$csvNormalNumberOfHeaderColumns" ] ; then
         echo -n "stopping now, since normal number of header columns has changed! Ask Neelima why? "
         echo "Observed file has $csvNumberOfHeaderColumns in the header, should be $csvNormalNumberOfHeaderColumns ."
         exit 1
      fi
      csvNumberOfFirstLineColumns=$(head -n 2 $csvFileName | awk -F, '{ print NF }' | tail -n 1)
      if [ "$csvNumberOfFirstLineColumns" != "$csvNumberOfNormalFirstLineColumns" ] ; then
         echo -n "stopping now, since number of first line columns has changed! Ask Neelima why? "
         echo "Observed file has $csvNumberOfFirstLineColumns in the first line of data, should be $csvNumberOfNormalFirstLineColumns ."
         exit 1
      fi
      echo -n "$(head -n 1 $csvFileName | awk -F, '{ print NF }') columns of data, should be $csvNormalNumberOfHeaderColumns columns, "
      ###
      ###
      getSTARTDATE
      ## csvFileNameOrigNumberOfLines=$(wc -l $csvFileName | awk '{ print $1 }')
      ## echo -n " $csvFileNameOrigNumberOfLines lines "

      reducedDotcsv="_reduced.csv"
      timestampReduced1="_timestamp_reduced"
      timestampReduced2="_timestamp_reduced2"
      timestampOnly1="_timestamp_only"
      reachableCalc="reachableCalc"
      headerRemovedDotcsv="__noHeader_ISO8601.csv"
      allCombined="all_combined_"
      # filename=$(basename $arg2)
      filenamePrefix=$(echo $csvFileName | cut -d '.' -f 1)
      filenameEnding=$(basename $csvFileName | cut -b 10-)

      ### Step 1) if input file's first field is exactly 26 chars in length, then
      ###         reduce that field to 19, saves to a temp file for step 2.
      ###
      echo -n "reduce col 1 Timestamp "
      awk -F, -vOFS=, '{{if(length($1)==26) {$1 = substr($1,1,19)}}};1' $csvFileName > $filenamePrefix$timestampReduced1
      echo -n "-done, "
      sleep 0.1

      ### Step 2) Take the temp file, substitue character underscore for T, also
      ###         29Nov2024: substitute character spacebar, compliant with SQL datetime format
      ###         remove the header with the tail -n +2 command, write the output to a file.
      ###
      echo -n "remove header make time ISO8601 compliant "
      ### awk -F, -vOFS=, '{sub("_","T",$1) }; 1' $filenamePrefix$timestampReduced1 | tail -n +2 > $filenamePrefix$timestampReduced2
      awk -F, -vOFS=, '{sub("_"," ",$1) }; 1' $filenamePrefix$timestampReduced1 | tail -n +2 > $filenamePrefix$timestampReduced2
      ### awk -F, -vOFS=, '{sub("_","T",$1) }; 1' $filenamePrefix$timestampReduced1 > $filenamePrefix$timestampReduced2
      echo -n "-done, "
      sleep 0.1

      ### Step 3) Take the temp file, make sure integer values such as software and
      ###         RU Hardware Version and manufacter date are made to be integers, 
      ###         DISH raw file stores them 3119.0 20220404.0 or 300.0
      ###         Also, removed any DOS/Windows characters with "tr -d '\r'" statement
      ###
      echo -n "correct 3119.0 to integer sort-u "
      awk -F, -vOFS=, -v fname="$csvFileName" '{ for (i = 1; i <= NF; i++) { if (i == 13 || i == 15 || i == 29) $i = int($i) } print $0, fname }' \
      "$filenamePrefix$timestampReduced2" | tr -d '\r' | sort -u > "$filenamePrefix$timestampReduced1$headerRemovedDotcsv"

      ## echo -n "-done, "
      ## echo -n "now reduce spaces "
      ## sed -i 's/  ,/,/g' $filenamePrefix$timestampReduced1$headerRemovedDotcsv
      ## sed -i 's/,  /,/g' $filenamePrefix$timestampReduced1$headerRemovedDotcsv

      echo -n "-done, "
      echo -n "now remove -NA- and other meaningless entries "
      sed -i 's/  -NA-  //g' $filenamePrefix$timestampReduced1$headerRemovedDotcsv
      echo -n "now remove -NC- and other meaningless entries "
      sed -i 's/  -NC-  //g' $filenamePrefix$timestampReduced1$headerRemovedDotcsv
      echo -n "now remove --:::--:::--:::--:::--:::--:::--:::--:::--:::-- and other meaningless entries "
      sed -i 's/--:::--:::--:::--:::--:::--:::--:::--:::--:::--//g' $filenamePrefix$timestampReduced1$headerRemovedDotcsv
      echo -n "now remove null and other meaningless entries "
      sed -i 's/null//g' $filenamePrefix$timestampReduced1$headerRemovedDotcsv
      echo -n "now remove 'Not Found' and other meaningless entries "
      sed -i 's/Not Found//g' $filenamePrefix$timestampReduced1$headerRemovedDotcsv
      ### sed -i 's/,  /,/g' $filenamePrefix$timestampReduced1$headerRemovedDotcsv

      csvFileNameReducedNumberOfLines=$(wc -l $filenamePrefix$timestampReduced1$headerRemovedDotcsv | awk '{ print $1 }')

      awk -F, '{ print $10 }' $csvFileName > $filenamePrefix$reachableCalc
      echo "-done, Counting RU failures: No pings, no SSH etc."
      numberOfReachableRUs=$(egrep Reachable $filenamePrefix$reachableCalc | wc -l)
      numberOfPingCSRFailures=$(egrep 'Ping to CSR Failed' $filenamePrefix$reachableCalc | wc -l)
      numberOfPingRUFailures=$(egrep 'Ping to RU Failed' $filenamePrefix$reachableCalc | wc -l)
      numberOfSSHRUFailures=$(egrep 'SSH to RU Failed' $filenamePrefix$reachableCalc | wc -l)
      reducedNumberOfLines=$(($csvFileNameOrigNumberOfLines-$csvFileNameReducedNumberOfLines))
      rm $filenamePrefix$reachableCalc

      getENDDATE
      sec_old=$(date -d "$STARTDATE" +%s)
      sec_new=$(date -d "$ENDDATE" +%s)
      ELAPSEDSECONDS=$(( sec_new - sec_old ))
      echo "-done, reduced by $reducedNumberOfLines lines "$(($ELAPSEDSECONDS%3600/60))"m "$(($ELAPSEDSECONDS%60))"s."

      rm $filenamePrefix$timestampReduced1
      rm $filenamePrefix$timestampReduced2
      
      awk -F, '{ print $1 }' $filenamePrefix$timestampReduced1$headerRemovedDotcsv > $filenamePrefix$timestampOnly1
      startTimestamp=$(date -d "$(sort $filenamePrefix$timestampOnly1 | head -n 1)" +%s)
      endingTimestamp=$(date -d "$(sort $filenamePrefix$timestampOnly1 | tail -n 1)" +%s)
      diffTimestampSeconds=$((endingTimestamp - startTimestamp))
      durationHours=$((diffTimestampSeconds / 3600))
      durationMinutes=$(( (diffTimestampSeconds % 3600) / 60 ))
      durationSeconds1=$((diffTimestampSeconds % 3600))
      durationSeconds=$((diffTimestampSeconds % 60))
      ### Below time format can be as complicated as: printf '%(%FT%T%z)T\n' 1234567890
      echo -n "Sampling window "$(printf '%(%F %T)T\n' $startTimestamp)" -> "$(printf '%(%T)T\n' $endingTimestamp)" UTC or ${durationHours}h ${durationMinutes}m ${durationSeconds}s "
      if (( $diffTimestampSeconds > 0 )) ; then
         echo "-> $diffTimestampSeconds seconds processed $(($csvFileNameOrigNumberOfLines/$diffTimestampSeconds)) RUs per sec."
      else
         echo "-> $diffTimestampSeconds seconds processed."
      fi
      rm $filenamePrefix$timestampOnly1
      # echo -n "Reachable RUs ${numberOfReachableRUs}/${csvFileNameOrigNumberOfLines}" $(((numberOfReachableRUs/csvFileNameOrigNumberOfLines)*100))
      # echo -n "Reachable RUs ${numberOfReachableRUs}/${csvFileNameOrigNumberOfLines} " $((100*(numberOfReachableRUs/csvFileNameOrigNumberOfLines)))
      echo -n "Reachable RUs ${numberOfReachableRUs}/${csvFileNameReducedNumberOfLines}"
      echo -n " | CSR Ping failures ${numberOfPingCSRFailures}/${csvFileNameReducedNumberOfLines}"
      echo -n " | RU Ping failures ${numberOfPingRUFailures}/${csvFileNameReducedNumberOfLines}"
      echo    " | SSH failures ${numberOfSSHRUFailures}/${csvFileNameReducedNumberOfLines}"
      # echo    ""
      echo "-------------------------------------------------------------------------------------------------------------"

      # echo "...Added $(wc -l $allCombined$filenameEnding | awk '{ print $1 }') lines"
      if [ -e ./delete ] ; then
         rm $csvFileName
         mv $filenamePrefix$timestampReduced1$headerRemovedDotcsv ./old_csv/
      else
         # echo "Nope, nothing."
         mv $csvFileName ./old_csv/
         mv $filenamePrefix$timestampReduced1$headerRemovedDotcsv ./old_csv/
      fi
      # cp  $allCombined$filenameEnding /cygdrive/c/Users/mitchepe/Downloads/
      # echo "done"
      # exit 0
   else
      # echo "file(s) not found"
      # echo -n "."
      sleep 1
   fi # Exists ru_final_*.csv in current directory
   echo -n "."
   # touch stop ### Used as a debugging measure
   if [ -e ./once ] ; then
      echo "Once marker detected... so stopping"
      exit 0
   fi
   sleep 5
   echo -n "."
done
# echo "."
# sleep 5
exit 0
