ffmpeg -i ./*.flv -vcodec libvpx -acodec libvorbis deskshare.webm
#ffmpeg -c:v libvpx -crf 34 -b:v 60M -threads 2 -deadline good -cpu-used 3 -c:a libvorbis -b:a 48K -f webm
