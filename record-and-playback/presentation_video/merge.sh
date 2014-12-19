DESKSHARE_DELAY=7

ffmpeg -i video.webm -i deskshare.webm -filter_complex "[0:v] setpts=PTS-STARTPTS, scale=1222x604 [base]; [1:v] setpts=PTS-STARTPTS+$DESKSHARE_DELAY/TB, scale=810x604 [deskshare]; [base][deskshare] overlay=w:x=0:y=0" -c:a libvorbis -b:a 48K -f webm myout.webm
