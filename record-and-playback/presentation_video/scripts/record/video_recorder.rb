require '../../core/lib/recordandplayback'
require '../../core/lib/recordandplayback/generators/video'
require 'yaml'
require 'open-uri'
require 'uri'

module BigBlueButton

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

			if duration == ''
				BigBlueButton.logger.info "No duration field at metadata.xml. Will extract video time from audio.webm or webcams.webm"

				uri = URI.parse(link)
			    file_repo = "#{uri.scheme}://#{uri.host}/presentation/#{record_id}"

				BigBlueButton.try_download "#{file_repo}/video/webcams.webm", "#{@target_dir}/webcams.webm"
			    BigBlueButton.try_download "#{file_repo}/audio/audio.webm", "#{@target_dir}/audio.webm"

			    audio_file = nil
			    if File.exist?("#{@target_dir}/webcams.webm")
			      audio_file = "#{@target_dir}/webcams.webm"
			    elsif File.exist?("#{@target_dir}/audio.webm")
			      audio_file = "#{@target_dir}/audio.webm"
			    else
			      BigBlueButton.logger.error "Couldn't locate an audio file on published presentation"
			      raise "NoAudioFile"
			    end	

			    BigBlueButton.logger.info "Will extract audio lenght from #{audio_file}"
			    FFMPEG.ffmpeg_binary = "/usr/local/bin/ffmpeg"
			    BigBlueButton.logger.info "Setting FFMPEG path to #{FFMPEG.ffmpeg_binary}"
			    # Must transform to ms
			    duration = "#{BigBlueButton.get_video_duration(audio_file)}".to_f * 1000
			    BigBlueButton.logger.info "Extracted duration: #{duration}"

			    BigBlueButton.logger.info "Deleting #{audio_file}"
			    FileUtils.rm_rf audio_file			    
			end			

			BigBlueButton.logger.info "record_id: #{record_id}"
			BigBlueButton.logger.info "format   : #{format}"
			BigBlueButton.logger.info "duration : #{duration} ms"
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

			BigBlueButton.logger.info("Recording of meeting #{@meeting_id} set up.")

			if format != "presentation"
				BigBlueButton.logger.error "This video recorder works with the presentation format only. Format #{format} is invalid."
				raise "InvalidFormat"
			end
		end

		def prepare_browser
			ENV["DISPLAY"] = ":#{@display_id}"

			display_settings = $props['display_settings']
			command = "Xvfb :#{@display_id} -nocursor -screen 0 #{display_settings}"
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
			sleep firefox_safemode_wait

			# Close the safe mode warning
			command = "xdotool key Return"
			BigBlueButton.execute(command)

			# Click to close the Mozilla Foundation message
			sleep firefox_safemode_wait
			command = "xdotool mousemove #{firefox_width - 14} 100"
			BigBlueButton.execute(command)
			command = "xdotool click 1"
			BigBlueButton.execute(command)

			# Wait presentation to load
			firefox_load_wait = $props['firefox_load_wait']
			sleep firefox_load_wait

			# Move mouse to start playing the video
			play_button_x_position = $props['play_button_x_position']
			play_button_y_position = $props['play_button_y_position']
			command = "xdotool mousemove #{play_button_x_position} #{play_button_y_position}"
			BigBlueButton.execute(command)
			command = "xdotool click 1"
			BigBlueButton.execute(command)
		end

		def wait_recording
			BigBlueButton.logger.info "Waiting #{@duration} seconds until the end of the recording"
			sleep @duration
		end

		def record_with_recordmydesktop(width, height, x, y, output)
			BigBlueButton.logger.info "Recording with recordmydesktop"
			command = "recordmydesktop --overwrite --on-the-fly-encoding --no-cursor --no-sound --fps 30 --width #{width} --height #{height} -x #{x} -y #{y} -o #{output}"
			@recordmydesktop = BigBlueButton.execute_async(command)

			self.wait_recording

			BigBlueButton.kill(@recordmydesktop)
			BigBlueButton.wait(@recordmydesktop, @duration)

			session_dir = "/tmp/rMD-session-#{@display_id}"
			if BigBlueButton.dir_exists? session_dir
				command = "recordmydesktop --overwrite --rescue #{session_dir}"
				BigBlueButton.execute command
				FileUtils.rm_r session_dir
			else
				# probably the file got recorded properly
			end
			@recordmydesktop = nil
		end

		def record_with_ffmpeg(width, height, x, y, output)
			BigBlueButton.logger.info "Recording with ffmpeg"
			ffmpeg_cmd = BigBlueButton::EDL::FFMPEG
			ffmpeg_cmd += [
				'-y',
				'-an',
				'-t', "#{@duration}",
				'-f', 'x11grab',
				'-s', "#{width}x#{height}",
				'-i', ":#{@display_id}.0+#{x},#{y}",
				'-c:v', 'libvpx',
				'-qmin', '0', '-qmax', '50',
				'-crf', '5', '-b:v', '1M',
				"#{output}"
			]
			BigBlueButton.exec_ret(*ffmpeg_cmd)
		end

		def record_screen
			recorded_screen_raw_file = "#{@target_dir}/recorded_screen_raw.webm"
			BigBlueButton.logger.info("Raw file: #{recorded_screen_raw_file}")

			record_window_width = $props['record_window_width']
			record_window_height = $props['record_window_height']
			record_window_x_offset = $props['record_window_x_offset']
			record_window_y_offset = $props['record_window_y_offset']
			# record_with_recordmydesktop(record_window_width, record_window_height, record_window_x_offset, record_window_y_offset, recorded_screen_raw_file)
			record_with_ffmpeg(record_window_width, record_window_height, record_window_x_offset, record_window_y_offset, recorded_screen_raw_file)
		end

		def tear_down
			Process.detach @firefox.pid
			BigBlueButton.kill(@firefox)
			@firefox = nil

			BigBlueButton.kill(@xvfb)
			BigBlueButton.wait(@xvfb)
			@xvfb = nil
		end

		def force_kill(proc)
				if not proc.nil?
						begin
								BigBlueButton.logger.info "Killing PID #{proc.pid}"
								BigBlueButton.kill(proc, "KILL")
						rescue Exception => e
								BigBlueButton.logger.error "Error while killing PID #{proc.pid}"
						end
				end
		end

		# This converts a playback meeting and outputs a out.avi file at bigbluebutton/published/#{meeting_id}
		#
		#   meeting_id - meeting id of video to be converted
		def record(metadata_url, display_id)
			@metadata_url = metadata_url
			@display_id = display_id

			begin
				self.set_up
				self.prepare_browser
				self.record_screen
				self.tear_down

				recording_dir = $bbb_props['recording_dir']
				process_done = File.new("#{recording_dir}/status/processed/#{@meeting_id}-presentation_recorder.done", "w")
				process_done.write("Processed #{@meeting_id}")
				process_done.close
			rescue Exception => e
				BigBlueButton.logger.error "Exception ocurred during video record: #{e.message}"

				e.backtrace.each do |traceline|
					BigBlueButton.logger.error(traceline)
				end

				self.force_kill(@recordmydesktop)
				self.force_kill(@firefox)
				self.force_kill(@xvfb)

				FileUtils.rm_rf @target_dir

				raise e
			end
		end
	end
end
