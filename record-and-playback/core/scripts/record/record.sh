# @author Felipe Mathias Schmidt, PRAV - MConf (UFRGS)
#
# This script creates a virtual display, fires an instance of firefox inside it with a video link. Firefox version used
# is 27.0; the web-browser must be previously configurated, creating as much profiles as desired to your recording pool
# (number of simultaneous recording). Profile names must be the same as the virtual display ID (e.g: 99).
# By the end of this process, all used programs are closed/terminated.
#
# Parameters
# $1 - first parameter must be the DISPLAY_ID, an unique ID that identifies the virtual display
# $2 - second parameter must be the TIME to be recorded in seconds
# $3 - third parameter is the WEB_LINK of the video you want to record
# $4 - fourth parameter is the OUTPUT_PATH of video file
#
# For further configuration you can change the 'record.conf' file, sourced in the beggining of this script.

# Configuration file to main recording parameters
. /usr/local/bigbluebutton/core/scripts/record/record.conf

# Input parameters
DISPLAY_ID=$1
TIME=$2
WEB_LINK=$3
OUTPUT_PATH=$4

export DISPLAY=:$DISPLAY_ID

# Create new Xvfb display
Xvfb :$DISPLAY_ID -nocursor -screen 0 $DISPLAY_SETTING &
XVFB_PID=$!

FIREFOX_HOME=/tmp/firefox_presentation_video
FIREFOX_PROFILE=$FIREFOX_HOME/new_profile/

rm -rf $FIREFOX_HOME
mkdir -p $FIREFOX_HOME
mkdir -p $FIREFOX_PROFILE

# Open firefox on new display
HOME=$FIREFOX_HOME firefox -profile $FIREFOX_PROFILE -safe-mode -width $FIREFOX_WIDTH -height $FIREFOX_HEIGHT -new-window $WEB_LINK &
FIREFOX_PID=$!

# Press enter to skip safemode
sleep $SAFEMODE_WAIT
xdotool key Return

# Click to close the Mozilla Foundation message
sleep $SAFEMODE_WAIT
xdotool mousemove $(($FIREFOX_WIDTH - 14)) 100
xdotool click 1

#Get meeting id from web link
MEETING_ID=$(echo $WEB_LINK | cut -d '=' -f2)

# Move mouse to start playing the video
sleep $FIREFOX_LOAD_WAIT

xdotool mousemove $PLAY_BUTTON_X_POSITION $PLAY_BUTTON_Y_POSITION
xdotool click 1

# Start recording
recordmydesktop --full-shots --no-cursor --no-sound --width $RECORD_WINDOW_WIDTH --height $RECORD_WINDOW_HEIGHT -x $RECORD_WINDOW_X_OFFSET -y $RECORD_WINDOW_Y_OFFSET -o $OUTPUT_PATH &
RECORD_PID=$!

# Sleep used to keep recording for the defined time
sleep $TIME

# Finish recording and start storing the video
kill -s 15 $RECORD_PID

kill -s 15 $FIREFOX_PID

# Waiting to store the recorded video
wait $RECORD_PID

kill -s 15 $XVFB_PID

echo "Recording at display $DISPLAY_ID during $TIME seconds terminated."

#Just to make sure we don't have a lock file unabling us to use again the same display id
#rm /tmp/.X$DISPLAY_ID-lock