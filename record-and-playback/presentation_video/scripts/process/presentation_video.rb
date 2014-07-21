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

opts = Trollop::options do
  opt :meeting_id, "Meeting id to archive", :default => '58f4a6b3-cd07-444d-8564-59116cb53974', :type => String
end

meeting_id = opts[:meeting_id]

# This script lives in scripts/archive/steps while properties.yaml lives in scripts/
bbb_props = YAML::load(File.open('../../core/scripts/bigbluebutton.yml'))
recording_dir = bbb_props['recording_dir']

props = YAML::load(File.open('presentation_video.yml'))
presentation_published_dir = props['presentation_published_dir']
presentation_unpublished_dir = props['presentation_unpublished_dir']
playback_dir = props['playback_dir']

target_dir = "#{recording_dir}/process/presentation_video/#{meeting_id}"
BigBlueButton.logger.debug "Testing if #{target_dir} exists"

if not FileTest.directory?(target_dir)
  # this recording has never been processed

  recorder_done = "#{recording_dir}/status/processed/#{meeting_id}-presentation_recorder.done"
  BigBlueButton.logger.debug "Testing if #{recorder_done} exists"

  if File.exists?(recorder_done)
    # the video was recorded, now it's time to prepare everything

    FileUtils.mkdir_p target_dir

    FileUtils.mkdir_p "/var/log/bigbluebutton/presentation_video"
    BigBlueButton.logger = Logger.new("/var/log/bigbluebutton/presentation_video/process-#{meeting_id}.log", 'daily' )

    presentation_recorder_dir = "#{recording_dir}/process/presentation_recorder/#{meeting_id}"
    recorded_screen_raw_file = "#{presentation_recorder_dir}/recorded_screen_raw.ogv"

    FileUtils.cp_r "#{presentation_recorder_dir}/metadata.xml", "#{target_dir}/metadata.xml"
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

    duration = doc.xpath('//recording/playback/duration').text
    link = doc.xpath('//recording/playback/link').text
    uri = URI.parse(link)
    file_repo = "#{uri.scheme}://#{uri.host}/presentation/#{meeting_id}"

    BigBlueButton.try_download "#{file_repo}/video/webcams.webm", "#{target_dir}/webcams.webm"
    BigBlueButton.try_download "#{file_repo}/audio/audio.webm", "#{target_dir}/audio.webm"

    audio_file = nil
    if File.exist?("#{target_dir}/webcams.webm")
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
        '-c:a', 'libvorbis', '-b:a', '32K',
        '-f', 'webm' ]
      ]
    }

    converted_video_file = "#{target_dir}/video"
    BigBlueButton::EDL::encode(audio_file, recorded_screen_raw_file, format, converted_video_file, 0)

    FileUtils.rm recorder_done
    FileUtils.rm_r(Dir.glob("#{presentation_recorder_dir}/*"))

    process_done = File.new("#{recording_dir}/status/processed/#{meeting_id}-presentation_video.done", "w")
    process_done.write("Processed #{meeting_id}")
    process_done.close
  end
end
