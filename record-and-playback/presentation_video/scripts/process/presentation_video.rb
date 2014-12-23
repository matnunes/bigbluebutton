# Set encoding to utf-8
# encoding: UTF-8

#
# BigBlueButton open source conferencing system - http://www.bigbluebutton.org/
#
# Copyright (c) 2012 BigBlueButton Inc. and by respective authors (see below).
#
# This program is free software; you can redistribute it and/or modify it under the
# terms of the GNU Lesser General Public License as published by the Free Software
# Foundation; either version 3.0 of the License, or (at your option) any later
# version.
#
# BigBlueButton is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License along
# with BigBlueButton; if not, see <http://www.gnu.org/licenses/>.
#

require File.expand_path('../../../lib/recordandplayback', __FILE__)
require 'rubygems'
require 'trollop'
require 'yaml'
require 'uri'

# Rap-worker generates the .fail file in case that this script dont generate the required .done

opts = Trollop::options do
  opt :meeting_id, "Meeting id to archive", :default => '58f4a6b3-cd07-444d-8564-59116cb53974', :type => String
end

meeting_id = opts[:meeting_id]

# This script lives in scripts/archive/steps while properties.yaml lives in scripts/
bbb_props = YAML::load(File.open('../../core/scripts/bigbluebutton.yml'))
recording_dir = bbb_props['recording_dir']
log_dir = bbb_props['log_dir']

props = YAML::load(File.open('presentation_video.yml'))
presentation_published_dir = props['presentation_published_dir']
presentation_unpublished_dir = props['presentation_unpublished_dir']
playback_dir = props['playback_dir']

recorder_props = YAML::load(File.open('mconf-presentation-recorder.yml'))
presentation_recorder_dir = recorder_props['presentation_recorder_dir']

FileUtils.mkdir_p "/var/log/bigbluebutton/presentation_video"
BigBlueButton.logger = Logger.new("#{log_dir}/presentation_video/process-#{meeting_id}.log", 'daily' )

# Create target_dir in advance in order to allow rap-worker to write its processing time in this folder
target_dir = "#{recording_dir}/process/presentation_video/#{meeting_id}"
FileUtils.mkdir_p target_dir

recorder_done = "#{recording_dir}/status/published/#{meeting_id}-presentation_recorder.done"
BigBlueButton.logger.info "Testing if presentation_recorder finished for meeting #{meeting_id}"

if File.exists?(recorder_done)

  # Check if publish of presentation_video failed and force it to be restarted after process is done.
  published_fail = "#{recording_dir}/status/published/#{meeting_id}-presentation_video.fail"    
  if File.exists?(published_fail)
    FileUtils.rm(published_fail)
  end

  # The video was recorded, now it's time to prepare everything
  presentation_recorder_meeting_dir = "#{presentation_recorder_dir}/#{meeting_id}"
  recorded_screen_raw_file = "#{presentation_recorder_meeting_dir}/recorded_screen_raw.webm"

  FileUtils.cp_r "#{presentation_recorder_meeting_dir}/metadata.xml", "#{target_dir}/metadata.xml"
  FileUtils.cp_r "#{recorded_screen_raw_file}", "#{target_dir}/"

  metadata = "#{target_dir}/metadata.xml"
  BigBlueButton.logger.info "Parsing metadata on #{metadata}"
  doc = nil
  begin
    doc = Nokogiri::XML(open(metadata).read)
  rescue Exception => e
    BigBlueButton.logger.error "Something went wrong: #{$!}"
    raise e
  end

  link = doc.xpath('//recording/playback/link').text
  uri = URI.parse(link)
  file_repo = "#{uri.scheme}://#{uri.host}/presentation/#{meeting_id}"

  BigBlueButton.try_download "#{file_repo}/video/webcams_no_deskshare.webm", "#{target_dir}/webcams_no_deskshare.webm"
  
  if !File.exists?("#{target_dir}/webcams_no_deskshare.webm")
    BigBlueButton.try_download "#{file_repo}/video/webcams.webm", "#{target_dir}/webcams.webm"
  end
  BigBlueButton.try_download "#{file_repo}/audio/audio.webm", "#{target_dir}/audio.webm"

  audio_file = nil
  # Does not make any difference if we take the webcams with or without deskshare. They have the same length
  if File.exist?("#{target_dir}/webcams_no_deskshare.webm")
    audio_file = "#{target_dir}/webcams_no_deskshare.webm"
  elsif File.exist?("#{target_dir}/webcams.webm")
    audio_file = "#{target_dir}/webcams.webm"
  elsif File.exist?("#{target_dir}/audio.webm")
    audio_file = "#{target_dir}/audio.webm"
  else
    BigBlueButton.logger.error "Couldn't locate an audio file on published presentation"
    raise "NoAudioFile"
  end

  format = {
    :extension => 'webm',
    :parameters => [
      [ '-c:v', 'libvpx', '-crf', '34', '-b:v', '60M',
      '-threads', '2', '-deadline', 'good', '-cpu-used', '3',
      '-c:a', 'copy', '-b:a', '32K',
      '-f', 'webm' ]
    ]
  }

  # Before we encode the video and execute mkclean, merge deskshare with recorded video
  events_xml = "/var/bigbluebutton/recording/raw/#{meeting_id}/events.xml"

  BigBlueButton.logger.info "Getting start events from #{events_xml}"

  deskshare_events = BigBlueButton::Events::get_start_deskshare_events(events_xml)

  deskshare_events.each do |deskshare_event|
    start_time = deskshare_event[:start_timestamp]
    deskshare_flv_file = "/var/bigbluebutton/deskshare/#{deskshare_event[:stream]}"
    BigBlueButton.logger.info "Start time #{start_time} flv file #{deskshare_flv_file}"

    #TODO
    # 1) get flv video infos (i.e. width, height)
    # 2) determines which dimension should be fixed
    # 2.1) scale the other dimension
    # 3) determine a good centralization to the video
    # 3.1) consider video width and height
    # 4) merge video
    #
    #
    #ffmpeg -i video.webm -i deskshare_flv_file -filter_complex
    #{}"[0:v] setpts=PTS-STARTPTS [presentation_video];
    #[1:v] setpts=PTS-STARTPTS+$DESKSHARE_DELAY/TB, scale=810:-2,
    #pad=width=$MAX_WIDTH:height=$MAX_HEIGHT:x=0:y=0:color=white [deskshare];
    #[presentation_video][deskshare] overlay=eof_action=pass:x=0:y=0"
    #-c:a libvorbis -b:a 48K -f webm myout.webm
  end

  video_before_mkclean = "#{target_dir}/before_mkclean"
  converted_video_file = "#{target_dir}/video"
  BigBlueButton::EDL::encode(audio_file, recorded_screen_raw_file, format, video_before_mkclean, 0)

  command = "mkclean --quiet #{video_before_mkclean}.#{format[:extension]} #{converted_video_file}.#{format[:extension]}"
  BigBlueButton.logger.info command
  BigBlueButton.execute command

  BigBlueButton.logger.info "Mkclean done"

  process_done = File.new("#{recording_dir}/status/processed/#{meeting_id}-presentation_video.done", "w")
  process_done.write("Processed #{meeting_id}")
  process_done.close

  BigBlueButton.logger.info "Process done!"
end