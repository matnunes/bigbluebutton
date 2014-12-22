DESKSHARE_DELAY=7

DESKSHARE_WIDTH=1222 
DESKSHARE_HEIGHT=604

MAX_WIDTH=810
MAX_HEIGHT=604

ffmpeg -i video.webm -i deskshare.webm -filter_complex "[0:v] setpts=PTS-STARTPTS [presentation_video]; [1:v] setpts=PTS-STARTPTS+$DESKSHARE_DELAY/TB, scale=810:-2, pad=width=$MAX_WIDTH:height=$MAX_HEIGHT:x=0:y=0:color=white [deskshare]; [presentation_video][deskshare] overlay=eof_action=pass:x=0:y=0" -c:a libvorbis -b:a 48K -f webm myout.webm
