
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

require '../lib/recordandplayback'
require 'rubygems'
require 'yaml'
require 'fileutils'

logger = Logger.new("/var/log/bigbluebutton/video-recorder-worker.log",'daily' )
logger.level = Logger::ERROR
BigBlueButton.logger = logger

def record_meeting
  props = YAML::load(File.open('bigbluebutton.yml'))  
  published_dir = props['published_dir']
  unpublished_dir = props['unpublished_dir']
  presentation_video_dir = props['presentation_video']

  while true
    Dir.exists?("#{published_dir}/presentation") ? 
      published_meetings = Dir.entries("#{published_dir}/presentation") - ['.','..'] :
      published_meetings = ['']

    Dir.exists?("#{unpublished_dir}/presentation") ? 
      unpublished_meetings = Dir.entries("#{unpublished_dir}/presentation") - ['.','..'] :
      unpublished_meetings = ['']  

    Dir.exists?("#{presentation_video_dir}") ? 
      recorded_meetings = Dir.entries("#{presentation_video_dir}") - ['.','..'] :
      recorded_meetings = ['']

    BigBlueButton.logger.error("Published: #{published_meetings}")
    BigBlueButton.logger.error("Unpublished: #{unpublished_meetings}")
    BigBlueButton.logger.error("Recorded: #{recorded_meetings}")

    meetings_to_record = published_meetings + unpublished_meetings - recorded_meetings - ['']

    BigBlueButton.logger.error("To record: #{meetings_to_record}")

    meetings_to_record.each do |mr|

      command = "ruby record/presentation_video.rb -m #{mr}"
      BigBlueButton.execute_background(command)

      BigBlueButton.logger.error("Meeting #{mr} added to pool")
    end

    # Sleep a while until searching for new meetings
    BigBlueButton.execute("sleep 30")
  end
end

record_meeting

BigBlueButton.logger.error("PROCESS TERMINATED")