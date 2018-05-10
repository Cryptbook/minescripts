#! /bin/bash
# Author: cryptbook@gmail.com
# ***   Description   ***
# nvidia-fan.sh script for controlling fan speed for Nvidia cards under Ubuntu 16.04
#
# Version 0.5.2
#
# Release notes
# 0.5.2 - change fan speed limits & some fixes in code
# 0.5.1 - fixed empty UUID for P106-100 cards
# 0.5 - output format changed
# 0.4 - added lock file, datetime stamp
# 0.3 - added export DISPLAY:0
# 0.2 - sh (shell) compability
# 0.1 - initial script version
# 
# Algo:
# 1) if gpu temperature  > 68 - maximum speed (=100)
# 2) if gpu temperature near high (>=65) and fan speed slow (<=80) set 80% fan speed
# 3) if gpu temperature low (<=55) and fan speed high (>=80) slow fan to 60%
# 4) if gpu temperature very low (<=45) and fan speed (>=60) slow fan to 40%
#
# Sources used:
# 1) https://gist.github.com/squadbox/e5b5f7bcd86259d627ed
# 2) https://gist.github.com/MihailJP/7318694
# 3) http://bencane.com/2015/09/22/preventing-duplicate-cron-job-executions/

calcTargetFanSpeed() #calculate new fan speed
{
        #$1 current GPU temperature
        #$2 current fan speed
        targetFanSpeed=$2
        if   [ $1 -ge 68 ]; then #overheating !!!
                targetFanSpeed=100
        else #normal temperature
                if [ $1 -ge 65 ] && [ $2 -le 80 ]; then  #high temperature low fan speed
                        targetFanSpeed=80 #increase fan speed
                elif [ $1 -le 55 ] && [ $2 -ge 80 ]; then #low temperature high fan speed
                        targetFanSpeed=60 #slow fan
                elif [ $1 -le 45 ] && [ $2 -ge 60 ]; then #low temperature high fan speed
                        targetFanSpeed=40 #very slow fan
                fi
        fi
        echo $targetFanSpeed
}

setTargetFanSpeed() #set fan speed
{
	#$1 nvidia-settings
	#$2 GPU number
	#$3 target fan speed (% percent)
        $1 -a [fan:$2]/GPUTargetFanSpeed=$3
}

pidFileWrite() #write PID file
{
	#$1 - path to PID file
	echo $$ > $1
        if [ $? -ne 0 ]
        then
        	echo "Could not create PID file"
         exit 1
        fi
}

#
# START PROGRAM
#

# Paths to the utilities we will need
SMI='/usr/bin/nvidia-smi'
SET='/usr/bin/nvidia-settings'
#PIDFILE check (check there is no instances of this script)
PIDFILE='/tmp/nvidia-fan.pid'
if [ -f $PIDFILE ]
then
	PID=$(cat $PIDFILE)
	ps -p $PID > /dev/null 2>&1
	if [ $? -eq 0 ]
	then
		echo "Job is already running. Stop execution."
    		exit 1
	else
		## Process not found assume not running
		pidFileWrite $PIDFILE
	fi
else
	pidFileWrite $PIDFILE
fi

# Determine major driver version
VER=`awk '/NVIDIA/ {print $8}' /proc/driver/nvidia/version | cut -d . -f 1`

# Drivers from 285.x.y on allow persistence mode setting
if [ ${VER} -lt 285 ]
then
    echo "Error: Current driver version is ${VER}. Driver version must be greater than 285."; exit 1;
fi

# how many GPU's are in the system?
NUMGPU="$(nvidia-smi -L | wc -l)"
# loop through each GPU and individually set parameters
n=0
export DISPLAY=:0
#xhost +
targetFanSpeed=80
#Out datetime stamp
echo "datetime,host,GPU,UUID,temperature,fanspeed_ASIS,fanspeed_TOBE,action"
while [  $n -lt  $NUMGPU ];
do
        #current N gpu temp
                gpuTemp=$($SET -q=[gpu:${n}]/gpucoretemp| grep '^  Attribute'| perl -pe 's/^.*?(\d+)\.\s*$/\1/;')
                #current N fan speed
        fanSpeed=$(${SET} -q [fan:${n}]/GPUTargetFanSpeed | grep '^  Attribute'| perl -pe 's/^.*?(\d+)\.\s*$/\1/;')
                #target N fan speed
        targetFanSpeed=$(calcTargetFanSpeed $gpuTemp $fanSpeed)
        #change speed only if needed
        if [ $fanSpeed -eq $targetFanSpeed ]; then
                statusFan="Skip ($fanSpeed)"
        else
                setTargetFanSpeed $SET ${n} $targetFanSpeed
                statusFan="SET $fanSpeed->$targetFanSpeed"
        fi
        #info
	UUID=`eval "${SMI}"' -L | awk '"'"'{n=index($0,"UUID"); if (substr($2,1,1)=='"${n}"') print substr($0,n+6,length($0)-n-6)}'"'"''`
        dt=$(date '+%Y%m%d %H:%M:%S');	
        echo "${dt},$HOSTNAME,GPU ${n},${UUID},$gpuTemp,$fanSpeed,$targetFanSpeed,$statusFan"
        #next gpu
        n=$(expr $n + 1)
done

#clean up PIDFILE
rm $PIDFILE
echo "Complete"; exit 0;
