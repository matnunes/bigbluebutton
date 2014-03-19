path = File.expand_path(File.join(File.dirname(__FILE__), '../generators'))
$LOAD_PATH << path

#require 'background_process'
require 'audio'
require 'yaml'
require 'thread'


module BigBlueButton

	# All necessary bash commands to output a video
	class VideoRecorder

		include Singleton

		# Load yaml file with recording properties
		$props = YAML::load(File.open('recorder.yml'))
		$bbb_props = YAML::load(File.open('../../../scripts/bigbluebutton.yml'))

		def initialize
			@virtual_displays = [*$props['display_first_id']..$props['display_last_id']]
			@display_mutex = Mutex.new
		end

		# Xvfb PID
		attr_accessor :xvfb

		# Initializes the virtual display using Xvfb
		#
		#   display_id - unique ID of virtual display
		def create_virtual_display(display_id)
			command = "Xvfb :#{display_id} -nocursor -screen 0 #{$props['display_setting']}"
			puts "Xvfb command : #{command}"
			BigBlueButton.logger.info("Task: Starting Xvfb virtual display with ID #{display_id}")
			#self.xvfb = BackgroundProcess.run(command)

			BigBlueButton.execute(command)

			# Wait a while until the virtual display is ready
			command = "sleep #{$props['xvfb_wait']}"
		end

		# Firefox PID
		attr_accessor :firefox

		# Fires firefox in virtual display with desired video
		#
		#   display_id - unique ID of virtual display
		#   video_link - link of video to be recorded
		def fire_firefox(display_id, video_link)
			main_props = "--display #{display_id} -p #{display_id} -new-window #{video_link}"
			size_props = "-width #{$props['firefox_width']} -height #{$props['display_height']}"
			command = "firefox #{main_props} #{size_props} &"

			BigBlueButton.logger.info("Task: Starting firefox in display ID #{display_id}")
			self.firefox = BackgroundProcess.run(command)

			puts "Firefox running? #{self.firefox.running?}"
		end

		# RecordMyDesktop PID
		attr_accessor :rmd

		# Records the desired video and flushes the data to disk
		#
		#   display_id - unique ID of virtual display
		#   millis - time to record movie in millis
		def record_video(display_id, millis)
			# Blocking is better to ensure we will wait until the video starts being recorded
			command = "DISPLAY=:#{display_id} xdotool mousemove #{$props['play_button_x_position']}
			#{$props['play_button_y_position']} & xdotool click 1"
			BigBlueButton.logger.info("Task: Playing video in display ID #{display_id} by clicking on play button")
			BackgroundProcess.run(command)

			main_props = "--display :#{display_id} --no-cursor --no-sound"
			size_props = "--width #{$props['record_window_width']} --height #{$props['record_window_height']}"
			offset_props = "-x #{$props['record_window_x_offset']} -y #{$props['record_window_y_offset']}"

			command = "recordmydesktop #{main_props} #{size_props} #{offset_props}"
			BigBlueButton.logger.info("Task: Recording video in display ID #{display_id} with #{millis}ms of duration")
			self.rmd = BackgroundProcess.run(command)

			# Transform milliseconds in seconds
			seconds = millis / 1000;

			command = "sleep #{seconds}"
			BigBlueButton.logger.info("Task: Waiting #{seconds} seconds until the end of the recording")
			BigBlueButton.execute(command)

			puts "RMD pid: #{self.rmd.pid}"
			self.rmd.kill("TERM")
			BigBlueButton.logger.info("Task: Recording process terminated. Flushing data to disk.")
			self.rmd.wait

			BigBlueButton.logger.info("Task: Data flushed!")
		end

		# Kills all used processes
		def kill_processes
			command = "kill -s 15 @firefox_pid @rmd_pid @xvfb_pid"
			BigBlueButton.logger.info("Task: Killing recording processes at display #{display_id}")
			BigBlueButton.execute(command)
		end

		# This is the easiest way to record a video as .ogv. This function just calls a shell script that must be stored as
		# ./scripts/record.sh
		#
		#   display_id - unique id of virtual display to be used
		#   seconds - seconds of video to be recorded
		#   web_link - link of video to be recorded
		#   output_path - path to where the video file must be outputed
		def record_by_script(display_id, seconds, web_link, output_path)
			command = "./scripts/record.sh #{display_id} #{seconds} #{web_link} #{output_path}"
			BigBlueButton.logger.info("Task: Recording on display #{display_id} during #{seconds} seconds")
			BigBlueButton.execute(command)
		end

		# SYNCHRONIZED: This pops a display id from display id list.
		def pop_free_display
			@display_mutex.synchronize do
				display_id = @virtual_displays.pop
				return display_id
			end
		end

		# SYNCHRONIZED: This 'gives back a display' by pushing the used id back to virtual display list 
		#
		#   display_id - id of used display
		def push_free_display(display_id)
			@display_mutex.synchronize do
				@virtual_displays.push(display_id)
			end
		end

		# This retrieves an available display id to be used. If no display is available after 20 seconds,
		# it returns nil
		#
		# @Return
		#   display_id - ID of virtual display
		def get_display_id
			display_id = self.pop_free_display
			sleep_count = 0

			while display_id == nil
				puts "Waiting for free display #{sleep_count}"
				sleep(2)
				sleep_count += 1
				display_id = self.pop_free_display

				if sleep_count >= 5
					puts "No virtual displays available, try again later!"
					return nil
				end
			end

			return display_id
		end

		# This merges a audio.ogv video with a video.ogg audio file and stores as ouput_video. File name and extension must
		# be included in path.
		#
		#   input_audio - complete path of audio.ogg
		#   input_video - complete path of video.ogv
		#   output_video - complete path of outputted video.ogv
		def merge_video_and_audio(input_ogg_audio, input_ogv_video, output_ogv_video)
			BigBlueButton.logger.info("Merging .ogv video to .ogg audio")
			command = "ffmpeg -i #{input_ogv_video} -i #{input_ogg_audio} -vcodec copy -acodec copy -acodec copy \
			#{output_ogv_video}"
			BigBlueButton.execute(command)

			BigBlueButton.logger.info("Deleting .ogv video without sound")
			command = "rm #{input_ogv_video}"
			BigBlueButton.execute(command)
		end	

		# Convert input .ogv file into output .wmv file. In path, the file name (with extension) must be included.
		#
		#   input_ogv - complete path of .ogv file
		#   output_wmv - complete path where .wmv file must be stored
		def ogv_to_wmv(input_ogv, output_wmv)
			BigBlueButton.logger.info("Converting .ogv to .wmv")
			command = "ffmpeg -i #{input_ogv} #{output_wmv}"
			BigBlueButton.execute(command)

			BigBlueButton.logger.info("Deleting temporary .ogv video file")
			command = "rm #{input_ogv}"
			#BigBlueButton.execute(command)
		end

		# Create .done status file of meeting_id after convertion
		#
		#   meeting_id - id of meeting
		def create_done(meeting_id)
			status_path = "#{$bbb_props['recording_dir']}/status"
			command = "touch #{status_path}/converted/#{meeting_id}.done"
			BigBlueButton.execute(command)
		end

		# This converts a playback meeting and outputs a out.avi file at bigbluebutton/published/#{meeting_id}
		#
		#   meeting_id - meeting id of video to be converted
		def record(meeting_id)
			output_path = "#{$bbb_props['published_dir']}/presentation/#{meeting_id}"
			audio_file = "#{$bbb_props['published_dir']}/presentation/#{meeting_id}/audio/audio.ogg"
			temp_video_file = "#{output_path}/video_temp.ogv"
			merged_audio_video = "#{output_path}/video.ogv"
			final_video_file = "#{output_path}/video.wmv"

			web_link = "#{$bbb_props['playback_host']}#{$props['playback_link_prefix']}#{meeting_id}"

			# Getting time in millis from wav file, will be the recording time
			audio_lenght = (BigBlueButton::AudioEvents.determine_length_of_audio_from_file(audio_file)) / 1000

			#audio_lenght = 3

			BigBlueButton.logger.info("Creating #{output_path}")
			command = "mkdir #{output_path}"
			#BigBlueButton.execute(command)

			# Get a free display
			display_id = self.get_display_id

			# Start the recording process
			self.record_by_script(display_id, audio_lenght, web_link, temp_video_file)			

			# Free used virtual display
			self.push_free_display(display_id)

			# Append audio to video file
			self.merge_video_and_audio(audio_file, temp_video_file, merged_audio_video)

			# Convert current video to avi
			self.ogv_to_wmv(merged_audio_video, final_video_file)

			# Done! Creating .done file
			self.create_done(meeting_id)
		end
	end
end