path = File.expand_path(File.join(File.dirname(__FILE__), '../generators'))
$LOAD_PATH << path

#
# Where method 'execute' is defined
# https://github.com/mconf/bigbluebutton/blob/master/record-and-playback/core/lib/recordandplayback.rb#L93

# Worker that includes everything and starts all the process
# https://github.com/mconf/bigbluebutton/blob/master/record-and-playback/core/scripts/rap-worker.rb#L22


require '../../recordandplayback'
#require '../../lib/recordandplayback'
require 'recorder'
#require '../generators/background_process'

require 'yaml'

vr = BigBlueButton::VideoRecorder.instance

t1 = Thread.new {
	#vr.convert("6e35e3b2778883f5db637d7a5dba0a427f692e91-1393606535521")
	vr.record("238ff79fd66331a59274a8f3f05f1c0cd3e278b4-1395254612095")
}

t2 = Thread.new {
	#vr.convert("8794e81667fa76fe8eba9a15ac4bea9d4396068a-1386418010870")
}

t1.join

t2.join