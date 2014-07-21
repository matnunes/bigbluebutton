require '../../core/lib/recordandplayback'
require 'yaml'
require 'open-uri'

module BigBlueButton

	# All necessary bash commands to output a video
	class VideoRecorder

		# Load yaml file with recording properties
		$props = YAML::load(File.open('mconf-presentation-recorder.yml'))
		$bbb_props = YAML::load(File.open('bigbluebutton.yml'))

		attr_accessor :target_dir
		attr_accessor :metadata_url
		attr_accessor :display_id
		attr_accessor :duration
		attr_accessor :link
		attr_accessor :meeting_id
		attr_accessor :xvfb
		attr_accessor :firefox
		attr_accessor :recordmydesktop

		def initialize
			@xvfb = nil
			@firefox = nil
			@recordmydesktop = nil
		end

		def parse_metadata(url)
			BigBlueButton.logger.info "Parsing metadata on #{url}"
			doc = nil
			begin
				doc = Nokogiri::XML(open(url).read)
			rescue Exception => e
				BigBlueButton.logger.error "Something went wrong: #{$!}"
				raise e
			end

			record_id = doc.xpath('//recording/id').text
			format = doc.xpath('//recording/playback/format').text
			duration = doc.xpath('//recording/playback/duration').text
			link = doc.xpath('//recording/playback/link').text

			BigBlueButton.logger.info "record_id: #{record_id}"
			BigBlueButton.logger.info "format   : #{format}"
			BigBlueButton.logger.info "duration : #{duration}"
			BigBlueButton.logger.info "link     : #{link}"

			return record_id, format, duration, link
		end

		def set_up
			BigBlueButton.logger.info("Creating target dir: #{@target_dir}")
			FileUtils.mkdir_p @target_dir

			metadata_xml = "#{@target_dir}/metadata.xml"
			BigBlueButton.download(@metadata_url, metadata_xml)

			@meeting_id, format, @duration, @link = parse_metadata(metadata_xml)
			@duration = @duration.to_f / 1000

			if format != "presentation"
				BigBlueButton.logger.error "This video recorder works with the presentation format only. Format #{format} is invalid."
				raise "InvalidFormat"
			end
		end

		def do_it
			recorded_screen_raw_file = "#{@target_dir}/recorded_screen_raw.ogv"
			BigBlueButton.logger.info("Raw file: #{recorded_screen_raw_file}")

			ENV["DISPLAY"] = ":#{display_id}"

			display_settings = $props['display_settings']
			command = "Xvfb :#{display_id} -nocursor -screen 0 #{display_settings}"
			@xvfb = BigBlueButton.execute_async(command)

			firefox_home = "/tmp/firefox_presentation_video"
			firefox_profile_dir = "#{firefox_home}/new_profile/"
			FileUtils.rm_rf firefox_home
			FileUtils.mkdir_p firefox_profile_dir

			firefox_width = $props['firefox_width']
			firefox_height = $props['firefox_height']
			command = "HOME=#{firefox_home} firefox -profile #{firefox_profile_dir} -safe-mode -width #{firefox_width} -height #{firefox_height} -new-window #{link}"
			@firefox = BigBlueButton.execute_async(command)

			firefox_safemode_wait = $props['firefox_safemode_wait']
			command = "sleep #{firefox_safemode_wait}"
			BigBlueButton.execute(command)

			command = "xdotool key Return"
			BigBlueButton.execute(command)

			# Click to close the Mozilla Foundation message
			command = "sleep #{firefox_safemode_wait}"
			BigBlueButton.execute(command)
			command = "xdotool mousemove #{firefox_width - 14} 100"
			BigBlueButton.execute(command)
			command = "xdotool click 1"
			BigBlueButton.execute(command)

			firefox_load_wait = $props['firefox_load_wait']
			command = "sleep #{firefox_load_wait}"
			BigBlueButton.execute(command)

			# Move mouse to start playing the video
			play_button_x_position = $props['play_button_x_position']
			play_button_y_position = $props['play_button_y_position']
			command = "xdotool mousemove #{play_button_x_position} #{play_button_y_position}"
			BigBlueButton.execute(command)
			command = "xdotool click 1"
			BigBlueButton.execute(command)

			record_window_width = $props['record_window_width']
			record_window_height = $props['record_window_height']
			record_window_x_offset = $props['record_window_x_offset']
			record_window_y_offset = $props['record_window_y_offset']
			command = "recordmydesktop --full-shots --no-cursor --no-sound --width #{record_window_width} --height #{record_window_height} -x #{record_window_x_offset} -y #{record_window_y_offset} -o #{recorded_screen_raw_file}"
			@recordmydesktop = BigBlueButton.execute_async(command)
		end

		def tear_down
			BigBlueButton.kill(@recordmydesktop)
			BigBlueButton.kill(@firefox, "KILL")

			# use a large wait timeout to be able to archive the entire recording
			BigBlueButton.wait(@recordmydesktop, @duration * 2)
			BigBlueButton.wait(@firefox, 10)

			BigBlueButton.kill(@xvfb)
			BigBlueButton.wait(@xvfb)
		end

		# This converts a playback meeting and outputs a out.avi file at bigbluebutton/published/#{meeting_id}
		#
		#   meeting_id - meeting id of video to be converted
		def record(metadata_url, display_id)
			@metadata_url = metadata_url
			@display_id = display_id

			begin
				self.set_up

				BigBlueButton.logger.info("Preparing to record meeting #{@meeting_id}.")

				self.do_it

				command = "sleep #{@duration}"
				BigBlueButton.execute(command)

				self.tear_down

				recording_dir = $bbb_props['recording_dir']
				process_done = File.new("#{recording_dir}/status/processed/#{@meeting_id}-presentation_recorder.done", "w")
				process_done.write("Processed #{@meeting_id}")
				process_done.close
			rescue Exception => e
				BigBlueButton.logger.error "Exception ocurred during video record: #{e.to_s}"
				BigBlueButton.kill(@recordmydesktop, "KILL") if not @recordmydesktop.nil?
				BigBlueButton.kill(@firefox, "KILL") if not @firefox.nil?
				BigBlueButton.kill(@xvfb, "KILL") if not @xvfb.nil?

				FileUtils.rm_rf @target_dir

				raise e
			end
		end
	end
end