
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

BigBlueButton.logger.error("I AM HEREE")

def record_meeting(meetings_dir)
  props = YAML::load(File.open('bigbluebutton.yml'))
  presentation_video_dir = props['presentation_video']

  if (Dir.exists?("#{meetings_dir}/presentation"))
    rec_meetings = Dir.entries("#{presentation_video_dir}") - ['.','..']
    proc_meetings = Dir.entries("#{meetings_dir}/presentation") - ['.','..']

    BigBlueButton.logger.error("Recorded: #{rec_meetings}")
    BigBlueButton.logger.error("Processed: #{proc_meetings}")

    # Ignore recorded meetings
    meetings_to_record = proc_meetings - rec_meetings

    BigBlueButton.logger.error("To record: #{meetings_to_record}")

    meetings_to_record.each do |mr|

      BigBlueButton.logger.error("Recording: #{mr}")    

      command = "sudo -u tomcat6 ruby record/presentation_video.rb -m #{meeting_id}"
      BibBlueButton.execute(command)

      BigBlueButton.logger.error("Function EXECUTED")
    end
  end
end

BigBlueButton.logger.error("NOW HEREE")

props = YAML::load(File.open('bigbluebutton.yml'))
published_dir = props['published_dir']
unpublished_dir = props['unpublished_dir']
record_meeting(published_dir)
record_meeting(unpublished_dir)

BigBlueButton.logger.error("IN THE END")