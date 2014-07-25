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
  logger = Logger.new("/var/log/bigbluebutton/presentation_video/publish-#{$meeting_id}.log", 'daily' )
  BigBlueButton.logger = logger
  # This script lives in scripts/archive/steps while properties.yaml lives in scripts/

  bbb_props = YAML::load(File.open('../../core/scripts/bigbluebutton.yml'))
  simple_props = YAML::load(File.open('presentation_video.yml'))
  BigBlueButton.logger.info("Setting recording dir")
  recording_dir = bbb_props['recording_dir']
  BigBlueButton.logger.info("Setting process dir")
  process_dir = "#{recording_dir}/process/presentation_video/#{$meeting_id}"
  BigBlueButton.logger.info("setting publish dir")
  publish_dir = simple_props['publish_dir']
  BigBlueButton.logger.info("setting playback host")
  playback_host = bbb_props['playback_host']
  BigBlueButton.logger.info("setting target dir")
  target_dir = "#{recording_dir}/publish/presentation_video/#{$meeting_id}"

  raw_archive_dir = "#{recording_dir}/raw/#{$meeting_id}"

  if not FileTest.directory?(target_dir)
    BigBlueButton.logger.info("Making dir #{target_dir}")
    FileUtils.mkdir_p target_dir

    metadata_xml = "#{process_dir}/metadata.xml"
    BigBlueButton.logger.info "Parsing metadata on #{metadata_xml}"
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
    BigBlueButton.logger.info("Making dir #{package_dir}")
    FileUtils.mkdir_p package_dir

    BigBlueButton.logger.info("Creating metadata.xml")
    
    metadata_xml = File.new("#{package_dir}/metadata.xml","w")
    metadata_xml.write(doc.to_xml(:indent => 2))
    metadata_xml.close

    FileUtils.cp_r("#{process_dir}/video.webm", "#{package_dir}/")

    if not FileTest.directory?(publish_dir)
      FileUtils.mkdir_p publish_dir
    end
    FileUtils.cp_r(package_dir, publish_dir) # Copy all the files.
    BigBlueButton.logger.info("Finished publishing script presentation_video.rb successfully.")

    BigBlueButton.logger.info("Removing processed files.")
    FileUtils.rm_r(Dir.glob("#{process_dir}/*"))

    BigBlueButton.logger.info("Removing published files.")
    FileUtils.rm_r(Dir.glob("#{target_dir}/*"))
  end

end
