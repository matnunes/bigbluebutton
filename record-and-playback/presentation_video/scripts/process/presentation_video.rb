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
max_deskshare_width = props['max_deskshare_width']

recorder_props = YAML::load(File.open('mconf-presentation-recorder.yml'))
presentation_recorder_dir = recorder_props['presentation_recorder_dir']
max_deskshare_height = recorder_props['record_window_height']

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

  recorded_screen_raw_target_file = "#{target_dir}/recorded_screen_raw.webm"

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

  record_start_stop_events = BigBlueButton::Events::get_start_and_stop_rec_events(events_xml)
  record_events = BigBlueButton::Events::match_start_and_stop_rec_events(record_start_stop_events)
  BigBlueButton.logger.info "Record events: #{record_events}"

  deskshare_events = BigBlueButton::Events::get_matched_start_stop_deskshare_events(events_xml)
  BigBlueButton.logger.info "Deskshare events: #{deskshare_events}"

  # For all record events, check if there are deskshare events in between the recording and
  # calculate its start time and stop time offsets
  video_processed_time = 0
  deskshare_video_duration = 0
  record_events.each do |record_event|
    record_start_time = record_event[:start_timestamp]
    record_stop_time = record_event[:stop_timestamp]

    BigBlueButton.logger.info "Processing recording from #{record_start_time}ns to #{record_stop_time}ns"

    deskshare_events.each do |deskshare_event|
      deskshare_start_time = deskshare_event[:start_timestamp]
      deskshare_stop_time = deskshare_event[:stop_timestamp]
      deskshare_flv_file = "/var/bigbluebutton/deskshare/#{deskshare_event[:stream]}"

      cutted_deskshare = "#{target_dir}/cutted_deskshare.flv"
      # Calculate deskshare video time padding. Cut videos if necessary.
      if (deskshare_start_time > record_start_time && deskshare_start_time < record_stop_time)
          deskshare_start_time_padding = (deskshare_start_time - record_start_time + video_processed_time) / 1000.0

          if (deskshare_stop_time > record_stop_time)
            # Video duration in seconds. Used to cut deskshare at end of recording.
            deskshare_video_duration = (record_stop_time - deskshare_start_time) / 1000.0

            #TODO: cut input deskshare videos to be just the part recorded
            #command = "ffmpeg -i deskshare_flv_file -t deskshare_video_duration -copy "
            #BigBlueButton.execute command

            #deskshare_flv_file = cutted_deskshare
          else
            deskshare_video_duration = (deskshare_stop_time - deskshare_start_time) / 1000.0            
          end
      else
        BigBlueButton.logger.info "Deskshare event of #{deskshare_flv_file} out of this recording time"
        next
      end

      deskshare_video_height = BigBlueButton.get_video_height(deskshare_flv_file)
      deskshare_video_width = BigBlueButton.get_video_width(deskshare_flv_file)  

      BigBlueButton.logger.info "Start time #{deskshare_start_time} flv file #{deskshare_flv_file}"
      BigBlueButton.logger.info "height #{deskshare_video_height} width #{deskshare_video_width}"

      scaled_width = max_deskshare_width
      scaled_height = max_deskshare_height

      deskshare_padding_area_ratio = Float(max_deskshare_width) / Float(max_deskshare_height)
      deskshare_video_ratio = Float(deskshare_video_width) / Float(deskshare_video_height)   

      width_offset = 0
      height_offset = 0

      BigBlueButton.logger.info "Deskshare padding area ratio #{deskshare_padding_area_ratio} video ratio #{deskshare_video_ratio}"

      # Scale deskshare video respecting its scale and centralize it
      #
      # We could use '-2' in the dimension to be scaled, but as we need to calculate the scalled height/width
      # to centralize the video anyway, we use our value instead.
      if (deskshare_padding_area_ratio < deskshare_video_ratio)      
        if (max_deskshare_width > deskshare_video_width)
          scaled_width = deskshare_video_width
        else
          scaled_width = max_deskshare_width
        end

        # based on: ratio = width / height
        expected_height = (Float(scaled_width) / Float(deskshare_video_ratio)).floor
        height_offset = ((max_deskshare_height - expected_height) / 2).floor
        width_offset = ((max_deskshare_width - scaled_width)/2).floor    

        (expected_height > max_deskshare_height) ?
            scaled_height = max_deskshare_height :
            scaled_height = expected_height
      else
        if (max_deskshare_height > deskshare_video_height)
          scaled_height = deskshare_video_height
        else
          scaled_height = max_deskshare_height
        end

        # based on: ratio = width / height
        expected_width = (Float(scaled_height) * Float(deskshare_video_ratio)).floor
        height_offset = ((max_deskshare_height - scaled_height) / 2).floor
        width_offset = ((max_deskshare_width - expected_width)/2).floor    

        (expected_width > max_deskshare_width) ?
            scaled_width = max_deskshare_width :
            scaled_width = expected_width
      end
    
      BigBlueButton.logger.info "Deskshare video scaled to #{scaled_width}x#{scaled_height}"
      BigBlueButton.logger.info "Deskshare video centralized at x:#{width_offset} y:#{height_offset}"

      raw_merged_video = "#{target_dir}/recorded_screen_raw_with_deskshare.webm"

      command = "ffmpeg -i #{recorded_screen_raw_target_file} -i #{deskshare_flv_file} -filter_complex \"
                  [0:v] setpts=PTS-STARTPTS [presentation_video];
                  [1:v] setpts=PTS-STARTPTS+#{deskshare_start_time_padding}/TB, scale=#{scaled_width}:#{scaled_height}, 
                  pad=width=#{max_deskshare_width}:height=#{max_deskshare_height}:x=#{width_offset}:y=#{height_offset}:color=white [deskshare];
                  [presentation_video][deskshare] overlay=eof_action=pass:x=0:y=0
                  \" -c:a libvorbis -b:a 48K -f webm #{raw_merged_video}"
      BigBlueButton.execute command

      if (File.exists?(raw_merged_video) && File.exists?(recorded_screen_raw_target_file))
        FileUtils.rm recorded_screen_raw_target_file
        FileUtils.mv(raw_merged_video, recorded_screen_raw_target_file)
      end
    end
    video_processed_time += record_stop_time - record_start_time
    BigBlueButton.logger.info "#{video_processed_time}ns from recorded presentation_video processed."
  end

  video_before_mkclean = "#{target_dir}/before_mkclean"
  converted_video_file = "#{target_dir}/video"
  BigBlueButton::EDL::encode(audio_file, recorded_screen_raw_target_file, format, video_before_mkclean, 0)

  command = "mkclean --quiet #{video_before_mkclean}.#{format[:extension]} #{converted_video_file}.#{format[:extension]}"
  BigBlueButton.logger.info command
  BigBlueButton.execute command

  BigBlueButton.logger.info "Mkclean done"

  process_done = File.new("#{recording_dir}/status/processed/#{meeting_id}-presentation_video.done", "w")
  process_done.write("Processed #{meeting_id}")
  process_done.close

  BigBlueButton.logger.info "Process done!"
end