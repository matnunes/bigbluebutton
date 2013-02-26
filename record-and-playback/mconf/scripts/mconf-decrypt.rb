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

require '../../core/lib/recordandplayback'
require 'rubygems'
require 'yaml'
require 'net/http'
require 'rexml/document'
require 'open-uri'
require 'digest/md5'


BigBlueButton.logger = Logger.new("/var/log/bigbluebutton/decrypt.log",'daily' )

bbb_props = YAML::load(File.open('../../core/scripts/bigbluebutton.yml'))
mconf_props = YAML::load(File.open('mconf.yml'))

private_key = mconf_props['private_key']
get_recordings_url = mconf_props['get_recordings_url']
recording_dir = bbb_props['recording_dir'] 
raw_dir = "#{recording_dir}/raw"
archived_dir = "#{recording_dir}/status/archived"

if not get_recordings_url.nil? and not get_recordings_url.empty?

  doc = Nokogiri::XML(Net::HTTP.get_response(URI.parse(get_recordings_url)).body)
  returncode = doc.xpath("//returncode")
  if returncode.empty? or returncode.text != "SUCCESS"
    raise "getRecordings didn't return success"
  end

  doc.xpath("//recording").each do |recording|
    record_id = recording.xpath(".//recordID").text
    recording.xpath(".//download/format").each do |format|
      type = format.xpath(".//type").text
      if type == "encrypted"
        meeting_id = record_id
        file_url = format.xpath(".//url").text
        key_file_url = format.xpath(".//key").text
        md5_value = format.xpath(".//md5").text

        encrypted_file = file_url.split("/").last
        decrypted_file = File.basename(encrypted_file, '.*') + ".zip"
        if not File.exist?("#{archived_dir}/#{meeting_id}.done") then
          Dir.chdir(raw_dir) do
            BigBlueButton.logger.info("Decrypting the recording #{meeting_id}")

            BigBlueButton.logger.debug("recordID = #{record_id}")
            BigBlueButton.logger.debug("file_url = #{file_url}")
            BigBlueButton.logger.debug("key_file_url = #{key_file_url}")
            BigBlueButton.logger.debug("md5_value = #{md5_value}")

            BigBlueButton.logger.info("Downloading the encrypted file to #{encrypted_file}")
            writeOut = open(encrypted_file, "wb")
            writeOut.write(open(file_url).read)
            writeOut.close

            md5_calculated = Digest::MD5.file(encrypted_file)

            if md5_calculated == md5_value
              BigBlueButton.logger.info("The calculated MD5 matches the expected value")
              key_file = key_file_url.split("/").last
              decrypted_key_file = File.basename(key_file, '.*') + ".txt"

              BigBlueButton.logger.info("Downloading the key file to #{key_file}")
              writeOut = open(key_file, "wb")
              writeOut.write(open(key_file_url).read)
              writeOut.close

              if key_file != decrypted_key_file
                command = "openssl rsautl -decrypt -inkey #{private_key} < #{key_file} > #{decrypted_key_file}"
                status = BigBlueButton.execute(command)
                if not status.success?
                  raise "Couldn't decrypt the random key with the server private key"
                end
                FileUtils.rm_r "#{key_file}"
              else
                BigBlueButton.logger.info("No public key was used to encrypt the random key")
              end

              command = "openssl enc -aes-256-cbc -d -pass file:#{decrypted_key_file} < #{encrypted_file} > #{decrypted_file}"
              status = BigBlueButton.execute(command)
              if not status.success?
                raise "Couldn't decrypt the recording file using the random key"
              end
       
              BigBlueButton::MconfProcessor.unzip("#{raw_dir}/#{meeting_id}", decrypted_file)

              archived_done = File.new("#{archived_dir}/#{meeting_id}.done", "w")
              archived_done.write("Archived #{meeting_id}")
              archived_done.close
              
              [ "#{encrypted_file}", "#{decrypted_file}", "#{decrypted_key_file}" ].each { |file|
                BigBlueButton.logger.info("Removing #{file}")
                FileUtils.rm_r "#{file}"
              }

              BigBlueButton.logger.info("Recording #{record_id} decrypted successfully")

            else
              BigBlueButton.logger.error("The calculated MD5 doesn't match the expected value")
              FileUtils.rm_f(encrypted_file)
            end
          end
        end
      end
    end
  end
end