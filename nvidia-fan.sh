
#!/bin/bash
# Author: cryptbook@gmail.com
# ***   Description   ***
# nvidia-fan.sh script for controlling fan speed for Nvidia cards under Ubuntu 16.04
#
# Algo:
# 1) if gpu temperature  > 68 - maximum speed (=100)
# 2) if gpu temperature near high (>=65) and fan speed slow (<=80) set 80% fan speed
# 3) if gpu temperature low (<=60) and fan speed high (>=80) slow fan to 60%
# 4) if gpu temperature very low (<=50) and fan speed (>=60) slow fan to 40%
#
# Used materials:
# 1) https://gist.github.com/squadbox/e5b5f7bcd86259d627ed
# 2) https://gist.github.com/MihailJP/7318694


calcTargetFanSpeed() #calculate new fan speed
{
		#$1 current GPU temperature
		#$2 current fan speed
        let targetFanSpeed=$2
        if   [ $1 -ge 68 ]; then #overheating !!!
                let targetFanSpeed=100
        else #normal temperature
                if [ $1 -ge 65 ] && [ $2 -le 80 ]; then  #high temperature low fan speed
                        let targetFanSpeed=80 #increase fan speed
                elif [ $1 -le 60 ] && [ $2 -ge 80 ]; then #low temperature high fan speed
                        let targetFanSpeed=60 #slow fan
                elif [ $1 -le 50 ] && [ $2 -ge 60 ]; then #low temperature high fan speed
                        let targetFanSpeed=40 #very slow fan
                fi
        fi
        echo $targetFanSpeed
}

setTargetFanSpeed() #set fan speed
{
        $1 -a [fan:$2]/GPUTargetFanSpeed=$3
}

# Paths to the utilities we will need
SMI='/usr/bin/nvidia-smi'
SET='/usr/bin/nvidia-settings'

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
xhost +
targetFanSpeed=80
echo "GPU,temperature,fanspeed_asis,fanspeed_tobe"
while [  $n -lt  $NUMGPU ];
do
        #current N gpu temp 
		gpuTemp=$($SET -q=[gpu:${n}]/gpucoretemp| grep '^  Attribute'| perl -pe 's/^.*?(\d+)\.\s*$/\1/;')
		#current N fan speed
        fanSpeed=$(${SET} -q [fan:${n}]/GPUTargetFanSpeed | grep '^  Attribute'| perl -pe 's/^.*?(\d+)\.\s*$/\1/;')
		#target N fan speed
        targetFanSpeed=$(calcTargetFanSpeed $gpuTemp $fanSpeed)
		#info
        echo "GPU ${n},$gpuTemp,$fanSpeed,$targetFanSpeed"
		#change speed only if needed
        if [ $fanSpeed -eq $targetFanSpeed ]; then
                echo "GPU ${n}:Fanspeed not changed ($fanSpeed)"
        else
                setTargetFanSpeed $SET ${n} $targetFanSpeed
                echo "GPU ${n}:Fanspeed changed $fanSpeed-->$targetFanSpeed"
        fi
		#next gpu
        let n=n+1
done

echo "Complete"; exit 0;