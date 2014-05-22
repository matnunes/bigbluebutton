# @author Felipe Mathias Schmidt, PRAV - MConf (UFRGS)
#
# This script creates a virtual display, fires an instance of firefox inside it with a given video link. Firefox version
# used is 27.0.
#
# Parameters
# $1 - first parameter must be the DISPLAY_ID, an unique ID that identifies the virtual display
# $2 - second parameter must be the TIME to be recorded in seconds
# $3 - third parameter is the WEB_LINK of the video you want to record
# $4 - fourth parameter is the OUTPUT_PATH of video file
#
# For further configuration you can change the 'record.conf' file, sourced in the beggining of this script.

# Configuration file to main recording parameters
. /usr/local/bigbluebutton/core/scripts/process/record.conf

# Input parameters
DISPLAY_ID=$1
TIME=$2
WEB_LINK=$3
OUTPUT_PATH=$4

# Create new Xvfb display
Xvfb :$DISPLAY_ID -nocursor -screen 0 $DISPLAY_SETTING &
XVFB=$!

# Open firefox on new display -p $DISPLAY_ID 
firefox -profile /tmp/presentation_video-firefox-profile/ -safe-mode --display :$DISPLAY_ID -width $FIREFOX_WIDTH -height $FIREFOX_HEIGHT -new-window $WEB_LINK &
FIREFOX=$!

# Xvfb :96 -screen 0 1400x768x24 &
# firefox -profile /tmp/presentation_video-firefox-profile/ -p 96 -safe-mode --display :96 -new-window www.terra.com.br &
# firefox -p 96 -safe-mode --display :96 -new-window www.terra.com.br &
# recordmydesktop --display :96 --no-sound
# DISPLAY=:96 xdotool key Return

# Press enter to skip safemode
sleep $SAFEMODE_WAIT
DISPLAY=:$DISPLAY_ID xdotool key Return

#Get meeting id from web link
MEETING_ID=$(echo $WEB_LINK | cut -d '=' -f2)

# Move mouse to start playing the video
sleep $FIREFOX_LOAD_WAIT

DISPLAY=:$DISPLAY_ID xdotool mousemove $PLAY_BUTTON_X_POSITION $PLAY_BUTTON_Y_POSITION
DISPLAY=:$DISPLAY_ID xdotool click 1

# Start recording
recordmydesktop --full-shots --display :$DISPLAY_ID --no-cursor --no-sound --width $RECORD_WINDOW_WIDTH --height $RECORD_WINDOW_HEIGHT -x $RECORD_WINDOW_X_OFFSET -y $RECORD_WINDOW_Y_OFFSET -o $OUTPUT_PATH &
RECORD=$!

DISPLAY=:$DISPLAY_ID xdotool key Return

# Sleep used to keep recording for the defined time
sleep $TIME

# Finish recording and start storing the video
kill -s 15 $RECORD

kill -s 15 $FIREFOX

# Waiting to store the recorded video
wait $RECORD

kill -s 15 $XVFB

echo "Recording at display $DISPLAY_ID during $TIME seconds terminated."

#Just to make sure we don't have a lock file unabling us to use again the same display id
#rm /tmp/.X$DISPLAY_ID-lock