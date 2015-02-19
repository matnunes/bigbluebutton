#!/usr/bin/ruby
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

Dir.chdir(File.expand_path(File.dirname(__FILE__)))

require '../lib/recordandplayback'
require 'rubygems'
require 'yaml'
require 'fileutils'
require 'pathname'

BigBlueButton.logger = Logger.new("/var/log/bigbluebutton/mconf-presentation-recorder-worker.log",'daily' )

$props = YAML::load(File.open('mconf-presentation-recorder.yml'))
$bbb_props = YAML::load(File.open('bigbluebutton.yml'))

def parent_dir(file)
  Pathname(file).each_filename.to_a[-2]
end

def metadata_to_record_id(metadata)
  parent_dir(metadata)
end

def is_display_free(display_id)
  command = "xdpyinfo -display :#{display_id}"
  begin
    BigBlueButton.execute(command)
  rescue
    return true
  end
  return false
end

def get_free_display
  while true
    candidate = rand(65536)
    return candidate if is_display_free(candidate)
  end
end

# This worker is instantiated only once by God.
# record_meeting has an infinite loop that looks for new meetings to record
def record_meeting
  published_dir = $bbb_props['published_dir']
  unpublished_dir = $bbb_props['unpublished_dir']
  recording_dir = $bbb_props['recording_dir']
  status_dir = "#{recording_dir}/status"
  presentation_recorder_dir = $props['presentation_recorder_dir']
  presentation_video_status_dir = $props['presentation_video_status_dir']

  record_in_progress = Hash[(Dir.entries("#{presentation_recorder_dir}") - ['.', '..']).map {|v| [v, nil]}]

  while true
    #all_meetings = Dir.glob("#{presentation_video_status_dir}/*.done").map {|v| File.basename(v).sub(/.done/,'')}
    all_meetings = Dir.glob("#{status_dir}/published/*-presentation.done").map {|v| File.basename(v).sub(/-presentation.done/, '')}
    recorded_meetings = Dir.glob("#{status_dir}/processed/*-presentation_recorder.done").map {|v| File.basename(v).sub(/-presentation_recorder.done/, '')}
    recorded_meetings.each do |k|
      BigBlueButton.wait record_in_progress[k] if not record_in_progress[k].nil?
      record_in_progress.delete k
    end

    failed_meetings = Dir.glob("#{status_dir}/processed/*-presentation_recorder.fail").map {|v| File.basename(v).sub(/-presentation_recorder.fail/, '')}
    failed_meetings.each do |k|
      BigBlueButton.kill record_in_progress[k] if not record_in_progress[k].nil?
      record_in_progress.delete k
      fail_file = "#{status_dir}/processed/#{k}-presentation_recorder.fail"
      BigBlueButton.logger.info "Error file #{fail_file}"
      FileUtils.rm fail_file

      done_file = "#{status_dir}/processed/#{k}-presentation_recorder.done"
      FileUtils.rm_f done_file
    end

    meetings_to_record = all_meetings - recorded_meetings - record_in_progress.keys
    meetings_to_record.sort! {|x,y| x.sub(/.*-/, "") <=> y.sub(/.*-/, "")}

    BigBlueButton.logger.info "All meetings (published + unpublished):\n#{BigBlueButton.hash_to_str(all_meetings)}"
    BigBlueButton.logger.info "Meetings already recorded:\n#{BigBlueButton.hash_to_str(recorded_meetings)}"
    BigBlueButton.logger.info "Meetings being recorded right now:\n#{BigBlueButton.hash_to_str(record_in_progress)}"
    BigBlueButton.logger.info "Meetings to record:\n#{BigBlueButton.hash_to_str(meetings_to_record)}"
    BigBlueButton.logger.info "Meetings with error: \n#{BigBlueButton.hash_to_str(failed_meetings)}"

    if not meetings_to_record.empty?

        # Flag used to avoid multiple recordings to be started simultaneously, which leads to black-screen recording
        record_started = false

        meetings_to_record.each do |record_id|          
          if !record_started
            BigBlueButton.logger.info "Trying to process meeting: #{record_id}"
            if record_in_progress.count >= $props['simultaneous_meetings']
              BigBlueButton.logger.info "Maximum number of simmultaneous meetings reached!"
            else
              metadata_xml = nil
              published_xml = "#{published_dir}/presentation/#{record_id}/metadata.xml"
              unpublished_xml = "#{unpublished_dir}/presentation/#{record_id}/metadata.xml"

              if File.exist?(published_xml)
                metadata_xml = published_xml
              elsif File.exist?(unpublished_xml)
                metadata_xml = unpublished_xml
              end

              if metadata_xml != nil
                # send to presentation_recorder the metadata xml
                command = "ruby record/presentation_recorder.rb -m #{metadata_xml} -d #{get_free_display}"
                record_in_progress[record_id] = BigBlueButton.execute_async(command)
                record_started = true
              else
                BigBlueButton.logger.info "No metadata.xml found for meetings #{record_id}."
                BigBlueButton.logger.info "Skipping meeting. Probably presentation didn't finish yet for this meeting."
              end
            end
          end
        end
    end

    sleep $props['worker_sleep_time']
  end
end

if not Dir.exists?("#{$props['presentation_recorder_dir']}")
    BigBlueButton.logger.info("Presentation recorder dir #{$props['presentation_recorder_dir']} does not exists, creating it")
    FileUtils.mkdir_p("#{$props['presentation_recorder_dir']}")
end

record_meeting

BigBlueButton.logger.info("Worker terminated")
