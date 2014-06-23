
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
require 'thread'

logger = Logger.new("/var/log/bigbluebutton/video-recorder-worker.log",'daily' )
logger.level = Logger::ERROR
BigBlueButton.logger = logger

$props = YAML::load(File.open('presentation_video.yml'))
$bbb_props = YAML::load(File.open('bigbluebutton.yml'))

$virtual_displays = [*$props['display_first_id']..$props['display_last_id']]
$display_mutex = Mutex.new 

$recordings = {}

# SYNCHRONIZED: This pops a display id from display id list.
def pop_free_display    
  $display_mutex.synchronize do
    display_id = virtual_displays.pop
    if display_id != nil
      BigBlueButton.logger.error("Got display ID: #{display_id}.")
    end
    return display_id
  end
end

# SYNCHRONIZED: This 'gives back a display' by pushing the used id back to virtual display list 
#
#   display_id - id of used display
def push_free_display(display_id)
  BigBlueButton.logger.error("Pushing used display ID #{display_id} back to display pool.")
  $display_mutex.synchronize do
    $virtual_displays.push(display_id)
  end
end

# This retrieves an available display id to be used. If no display is available after 20 seconds,
# it returns nil
#
# @Return
#   display_id - ID of virtual display
def get_free_display
  BigBlueButton.logger.error("Trying to get free display ID from display pool.")
  display_id = pop_free_display
  sleep_count = 0

  while display_id == nil
    BigBlueButton.logger.error("Waiting for free display ID.")
    sleep(2)
    sleep_count += 1
    display_id = pop_free_display

    if sleep_count >= 5
      BigBlueButton.logger.error("No free display after 5 tries. Returning nil.")
      return nil
    end
  end

  return display_id
end

def record_meeting
  props = YAML::load(File.open('bigbluebutton.yml'))  
  published_dir = props['published_dir']
  unpublished_dir = props['unpublished_dir']
  presentation_video_dir = props['presentation_video']

  while true
    #Criar passo de verificação pra ver se meeting foi corretamente gravada

    Dir.exists?("#{published_dir}/presentation") ?
      published_meetings = Dir.entries("#{published_dir}/presentation") - ['.','..'] :
      published_meetings = ['']

    Dir.exists?("#{unpublished_dir}/presentation") ? 
      unpublished_meetings = Dir.entries("#{unpublished_dir}/presentation") - ['.','..'] :
      unpublished_meetings = ['']  

    Dir.exists?("#{presentation_video_dir}") ? 
      recorded_meetings = Dir.entries("#{presentation_video_dir}") - ['.','..'] :
      recorded_meetings = ['']    

    # Search for completed recordings in order to push display back to pool
    recorded_meetings.each do |rec|
      if $recordings[rec] != nil
        BigBlueButton.logger.error("Meeting #{rec} recorded. Pushing display #{$recordings[rec][1]} back to display pool")        
        $virtual_displays.push($recordings[rec][1])
        $recordings[rec][0].kill
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

    # Worker is istantiated only once!
    meetings_to_record.each do |mr|

      #display_id = get_free_display
      display_id = $virtual_displays.pop

      if (display_id != nil)
        command = "ruby record/presentation_video.rb -m #{mr} -d #{display_id}"
        $recordings[mr] = [BigBlueButton.execute_background(command), display_id]
        BigBlueButton.logger.error("Meeting #{mr} added to pool")
      else
        BigBlueButton.logger.error("No free display. Meeting #{mr} will be recorded later.")
      end      
    end

    # Sleep a while until searching for new meetings
    BigBlueButton.execute("sleep 10")

=begin
    $recordings.each do |rec|
      BigBlueButton.logger.error("Process at display display #{rec[1]} running? #{rec[0].running?}")

      if not rec[0].running?
        BigBlueButton.logger.error("Pushing display #{rec[1]} back to display pool")
        $virtual_displays.push(rec[1])
        #push_free_display(rec[1])
        $recordings.delete(rec)
      end
    end
=end

  end
end

record_meeting

BigBlueButton.logger.error("Worker Terminated!")