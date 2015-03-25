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
require 'pathname'
require './record/video_recorder'

opts = Trollop::options do
  opt :metadata_xml, "Path to the recording metadata.xml", :default => "?", :type => String
  opt :display_id, "Display id to use", :default => '98', :type => String
end

metadata_xml = opts[:metadata_xml]
meeting_id = Pathname(metadata_xml).each_filename.to_a[-2]
display_id = opts[:display_id]

log_dir = "/var/log/bigbluebutton/presentation_recorder/"
if not Dir.exists?(log_dir)
    FileUtils.mkdir_p log_dir
end

BigBlueButton.logger = Logger.new("/var/log/bigbluebutton/presentation_recorder/process-#{meeting_id}.log", 'daily' )

# This script lives in scripts/archive/steps while properties.yaml lives in scripts/
bbb_props = YAML::load(File.open('../../core/scripts/bigbluebutton.yml'))
$recording_dir = bbb_props['recording_dir']
$published_dir = bbb_props['published_dir']
$unpublished_dir = bbb_props['unpublished_dir']

target_dir = "#{$recording_dir}/process/presentation_recorder/#{meeting_id}"

# This method is based on bigbluebutton-config/bin/bbb-record and its rebuild function
def presentation_video_restart(meeting_id)
  BigBlueButton.logger.info "Marking to restart presentation_video for this meeting:"
  BigBlueButton.logger.info "Deleting published and unpublished folder of presentation_video for meeting #{meeting_id}"

  # Delete (un)published files. It force presentation_video restart even if it was already processed
  FileUtils.rm_rf "#{$published_dir}/presentation_video/#{meeting_id}"
  FileUtils.rm_rf "#{$unpublished_dir}/presentation_video/#{meeting_id}"

  BigBlueButton.logger.info "Deleting done and fail status files of presentation_video for meeting #{meeting_id}"
  
  # Delete status files
  FileUtils.rm_f "#{$recording_dir}/status/processed/#{meeting_id}-presentation_video.done"
  FileUtils.rm_f "#{$recording_dir}/status/published/#{meeting_id}-presentation_video.done"
  FileUtils.rm_f "#{$recording_dir}/status/processed/#{meeting_id}-presentation_video.fail"
  FileUtils.rm_f "#{$recording_dir}/status/published/#{meeting_id}-presentation_video.fail"
end

BigBlueButton.logger.info("Testing if recording never processed.")

process_done = "#{$recording_dir}/status/processed/#{meeting_id}-presentation_recorder.done"

# This recording has never been processed
if not FileTest.directory?(process_done)  

  BigBlueButton.logger.info("Trying to record meeting #{meeting_id} at display #{display_id} using presentation_recorder.rb")

  video_recorder = BigBlueButton::VideoRecorder.new()
  video_recorder.target_dir = target_dir
  begin
    BigBlueButton.logger.info "Starting video recorder."
    video_recorder.record(metadata_xml, display_id)
    BigBlueButton.logger.info "Video recorder done."

    # After recording the meeting, we force the process and publish of presentation_video to restart
    presentation_video_restart(meeting_id)

    BigBlueButton.logger.info("presentation_recorder done!")
  rescue Exception => e

    # Treat SIGTERM in case of a bbb-record --rebuildVideo terminating an ongoing meeting recording, avoiding it
    # to create a .fail file
    if e.to_s.eql? "SIGTERM"
      BigBlueButton.logger.error "Received SIGTERM signal. Recording terminated!"
    else
      BigBlueButton.logger.error "Something went wrong on the record method: #{e.to_s}"

      BigBlueButton.logger.error "Creating error file for meeting #{meeting_id}"
      process_error = File.new("#{$recording_dir}/status/processed/#{meeting_id}-presentation_recorder.fail", "w")
      process_error.write("Error processing #{meeting_id}")
      process_error.close
    end
  end
end
