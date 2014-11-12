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
require 'zip'

opts = Trollop::options do
  opt :meeting_id, "Meeting id to archive", :default => '58f4a6b3-cd07-444d-8564-59116cb53974', :type => String
end

$meeting_id = opts[:meeting_id]
match = /(.*)-(.*)/.match $meeting_id
$meeting_id = match[1]
$playback = match[2]

puts $meeting_id
puts $playback

if ($playback == "presentation_video")
  BigBlueButton.logger = Logger.new("/var/log/bigbluebutton/presentation_video/publish-#{$meeting_id}.log", 'daily' )

  BigBlueButton.logger.info("Starting publish of presentation_video for meeting #{$meeting_id}")

  # This script lives in scripts/archive/steps while properties.yaml lives in scripts/
  bbb_props = YAML::load(File.open('../../core/scripts/bigbluebutton.yml'))
  recording_dir = bbb_props['recording_dir']
  playback_host = bbb_props['playback_host']

  presentation_video_props = YAML::load(File.open('presentation_video.yml'))
  publish_dir = presentation_video_props['publish_dir']

  raw_archive_dir = "#{recording_dir}/raw/#{$meeting_id}"
  process_dir = "#{recording_dir}/process/presentation_video/#{$meeting_id}"  
  target_dir = "#{recording_dir}/publish/presentation_video/#{$meeting_id}"

  if not FileTest.directory?(target_dir)
    BigBlueButton.logger.info("Creating target dir #{target_dir}")
    FileUtils.mkdir_p target_dir

    metadata_xml = "#{process_dir}/metadata.xml"
    BigBlueButton.logger.info "Parsing #{metadata_xml}"
    doc = nil
    begin
      doc = Nokogiri::XML(open(metadata_xml).read)
    rescue Exception => e
      BigBlueButton.logger.error "Something went wrong: #{$!}"
      raise e
    end

    doc.at("published").content = true;
    doc.at("format").content = "presentation_video"
    doc.at("link").content = "http://#{playback_host}/presentation_video/#{$meeting_id}/video.webm"

    package_dir = "#{target_dir}/#{$meeting_id}"
    BigBlueButton.logger.info("Creating package dir #{package_dir}")
    FileUtils.mkdir_p package_dir

    BigBlueButton.logger.info("Creating metadata.xml on package dir")
    
    metadata_xml = File.new("#{package_dir}/metadata.xml","w")
    metadata_xml.write(doc.to_xml(:indent => 2))
    metadata_xml.close

    begin
      FileUtils.cp_r("#{process_dir}/video.webm", "#{package_dir}/")
    rescue Exception => e
      BigBlueButton.logger.info("#{process_dir}/video.webm doesn't exists. Forcing process of presentation_video to re execute.")

      # Delete fail file
      process_fail="#{recording_dir}/status/processed/#{$meeting_id}-presentation_video.fail"
      if File.exists?(process_fail)
        FileUtils.rm(process_fail)
      end

      # Create sanity file to force process to be re executed
      sanity_done = "#{recording_dir}/status/sanity/#{$meeting_id}.done"
      if not File.exists?(sanity_done)
        sanity_done_file = File.new(sanity_done, "w")
        sanity_done_file.close
      end      

      BigBlueButton.logger.error "Something went wrong: #{$!}"
      raise e
    end

    if not FileTest.directory?(publish_dir)
      FileUtils.mkdir_p publish_dir
    end
    
    # Copy all the files.
    BigBlueButton.logger.info("Copying files from package dir to publish dir.")    
    FileUtils.cp_r(package_dir, publish_dir)

    BigBlueButton.logger.info("Removing processed files.")
    FileUtils.rm_r(Dir.glob("#{process_dir}/*"))

    BigBlueButton.logger.info("Removing target dir files.")
    FileUtils.rm_r(Dir.glob("#{target_dir}/*"))

    process_done = File.new("#{recording_dir}/status/published/#{$meeting_id}-presentation_video.done", "w")
    process_done.write("Processed #{$meeting_id}")
    process_done.close

    BigBlueButton.logger.info("Publishing script presentation_video.rb finished successfully.")
  end

end
