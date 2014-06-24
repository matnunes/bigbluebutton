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

$props = YAML::load(File.open('presentation_video.yml'))
$bbb_props = YAML::load(File.open('bigbluebutton.yml'))

# Pool of virtual displays ids
$virtual_displays = [*$props['display_first_id']..$props['display_last_id']]

# Hash that maintains info of recordings
# {key = meeting_id, value = [presentation_video background process, display_id]}
$recordings = {}

# This worker is istantiated only once by God.
# record_meeting has an infinite loop that looks for new meetings to record
def record_meeting
  #props = YAML::load(File.open('bigbluebutton.yml'))
  published_dir = $bbb_props['published_dir']
  unpublished_dir = $bbb_props['unpublished_dir']
  presentation_video_dir = $bbb_props['presentation_video']

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

    # For all completed meetings, see if they are still consuming a display_id from the pool
    recorded_meetings.each do |rec|
      if $recordings[rec] != nil
        BigBlueButton.logger.error("Meeting #{rec} recorded. Pushing display #{$recordings[rec][1]} back to display pool")

        # Get display_id from hash
        $virtual_displays.push($recordings[rec][1])

        # Kill the remaining process
        $recordings[rec][0].kill

        # Remove meeting from hash
        $recordings.delete(rec)
      end
    end

    # Create list of meetings being recorded
    in_progress = ['']
    $recordings.each do |met, d_id|
      in_progress.push(met)
    end

    meetings_to_record = published_meetings + unpublished_meetings - recorded_meetings - in_progress - ['']

    BigBlueButton.logger.error("Published: #{published_meetings}")
    BigBlueButton.logger.error("Unpublished: #{unpublished_meetings}")
    BigBlueButton.logger.error("Recorded: #{recorded_meetings}")
    BigBlueButton.logger.error("In progress: #{in_progress}")
    BigBlueButton.logger.error("To record: #{meetings_to_record}")    

    meetings_to_record.each do |mr|
      # Get a display ID from the pool      
      display_id = $virtual_displays.pop

      # Starts to record the meeting using presentation_video
      if (display_id != nil)
        command = "ruby record/presentation_video.rb -m #{mr} -d #{display_id}"
        $recordings[mr] = [BigBlueButton.execute_background(command), display_id]
        BigBlueButton.logger.error("Recording meeting #{mr} at display #{display_id}")
      else
        BigBlueButton.logger.error("No free display. Meeting #{mr} will be recorded later.")
      end      
    end

    # Sleep a while before searching for new meetings
    BigBlueButton.execute("sleep 30")
  end
end

record_meeting

BigBlueButton.logger.error("Worker Terminated!")