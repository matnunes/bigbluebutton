path = File.expand_path(File.join(File.dirname(__FILE__), '../generators'))
$LOAD_PATH << path

#
# Where method 'execute' is defined
# https://github.com/mconf/bigbluebutton/blob/master/record-and-playback/core/lib/recordandplayback.rb#L93

# Worker that includes everything and starts all the process
# https://github.com/mconf/bigbluebutton/blob/master/record-and-playback/core/scripts/rap-worker.rb#L22


require '../../recordandplayback'
#require '../../lib/recordandplayback'
require 'converter'
#require '../generators/background_process'

require 'yaml'

vr = BigBlueButton::VideoConverter.instance

t1 = Thread.new {
	vr.convert("8794e81667fa76fe8eba9a15ac4bea9d4396068a-1386418010870")
}

t2 = Thread.new {
	vr.convert("8794e81667fa76fe8eba9a15ac4bea9d4396068a-1386418010870")
}

t1.join

t2.join