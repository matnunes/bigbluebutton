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


path = File.expand_path(File.join(File.dirname(__FILE__), '../lib'))
$LOAD_PATH << path

require 'recordandplayback/audio_archiver'
require 'recordandplayback/events_archiver'
require 'recordandplayback/video_archiver'
require 'recordandplayback/presentation_archiver'
require 'recordandplayback/deskshare_archiver'
require 'recordandplayback/generators/events'
require 'recordandplayback/generators/audio'
require 'recordandplayback/generators/video'
require 'recordandplayback/generators/matterhorn_processor'
require 'recordandplayback/generators/audio_processor'
require 'recordandplayback/generators/presentation'
require 'open4'
require 'pp'
require 'absolute_time'

# Background process available at:
# https://github.com/timcharper/background_process
# https://rubygems.org/gems/background_process
require 'background_process'

require 'timeout'
require 'uri'

module BigBlueButton
  class MissingDirectoryException < RuntimeError
  end
  
  class FileNotFoundException < RuntimeError
  end

  class AsyncProcess
    attr_accessor :command
    attr_accessor :pid
    attr_accessor :stdin
    attr_accessor :stdout
    attr_accessor :stderr
  end

  class ExecutionStatus
    def initialize
      @output = []
      @errors = []
      @detailedStatus = nil
    end

    attr_accessor :output
    attr_accessor :errors
    attr_accessor :detailedStatus

    def success?
      @detailedStatus.success?
    end

    def exited?
      @detailedStatus.exited?
    end

    def exitstatus
      @detailedStatus.exitstatus
    end
  end
  
  # BigBlueButton logs information about its progress.
  # Replace with your own logger if you desire.
  #
  # @param [Logger] log your own logger
  # @return [Logger] the logger you set
  def self.logger=(log)
    @logger = log
  end
  
  # Get BigBlueButton logger.
  #
  # @return [Logger]
  def self.logger
    return @logger if @logger
    logger = Logger.new(STDOUT)
    logger.level = Logger::INFO
    @logger = logger
  end

  def self.redis_publisher=(publisher)
    @redis_publisher = publisher
  end

  def self.redis_publisher
    return @redis_publisher
  end
  
  def self.dir_exists?(dir)
    FileTest.directory?(dir)
  end
    
  def self.execute_async(command)
    BigBlueButton.logger.info("Executing async: #{command}")
    proc = AsyncProcess.new
    proc.command = command
    proc.pid, proc.stdin, proc.stdout, proc.stderr = Open4::popen4 proc.command
    BigBlueButton.logger.info("Process just created with PID #{proc.pid}")
    proc
  end

  # http://stackoverflow.com/a/3568291/1006288
  def self.is_running?(proc)
    begin
      Process.getpgid( proc.pid )
      true
    rescue Errno::ESRCH
      false
    end
  end

  def self.kill(proc, signal = "TERM")
    BigBlueButton.logger.info("Killing PID #{proc.pid} with signal #{signal}: #{proc.command}")

    if not is_running?(proc)
      BigBlueButton.logger.info "Trying to kill a process that isn't running, skipping"
      return
    end

    proc.stdin.close unless proc.stdin.closed?

    begin
      Process.kill signal, proc.pid
    rescue Exception => e
      if e.message == "No such process"
        BigBlueButton.logger.info "Trying to kill a process that doesn't exist anymore, skipping"
      else
        BigBlueButton.logger.error "Something went wrong while killing PID #{proc.pid}: #{e.to_s}"
        raise e
      end
    end
  end

  def self.wait(proc, timeout_sec=30, fail_on_error=true)
    BigBlueButton.logger.info("Waiting PID #{proc.pid} to die (max. #{timeout_sec} seconds): #{proc.command}")

    if not is_running?(proc)
      BigBlueButton.logger.info "Trying to wait a process that isn't running, skipping"
      return
    end

    begin
      Timeout::timeout(timeout_sec) {
        pid_returned, status = Process.waitpid2 proc.pid

        BigBlueButton.logger.info("Process status: #{status.to_s}")
        BigBlueButton.logger.info("Process exited? #{status.exited?}")

        out = proc.stdout.readlines
        BigBlueButton.logger.info( "stdout:\n #{Array(out).join()} ") unless out.empty?

        err = proc.stderr.readlines
        BigBlueButton.logger.error( "stderr:\n #{Array(err).join()} ") unless err.empty?

        if status.exited?
          BigBlueButton.logger.info("Success?: #{status.success?}")
          BigBlueButton.logger.info("Exit status: #{status.exitstatus}")
          if status.success? == false and fail_on_error
            raise "Execution failed"
          end
        end
      }
    rescue Timeout::Error
      BigBlueButton.logger.info("PID #{proc.pid} didn't ended in #{timeout_sec} seconds")
      if is_running?(proc)
        BigBlueButton.logger.error "PID #{proc.pid} is still running, raising an exception"
        raise
      else
        BigBlueButton.logger.info "PID #{proc.pid} is not running anymore, skipping"
      end
    rescue Exception => e
      if e.message == "No child processes"
        BigBlueButton.logger.info "Trying to wait a process that doesn't exist anymore, skipping"
      else
        BigBlueButton.logger.error "Something went wrong while waiting for PID #{proc.pid}: #{e.to_s}"
        raise e
      end
    end
    BigBlueButton.logger.debug "Returning from wait"
  end

  def self.execute(command, fail_on_error=true)
    status = ExecutionStatus.new
    status.detailedStatus = Open4::popen4(command) do | pid, stdin, stdout, stderr|
        begin
          BigBlueButton.logger.info("Executing sync: #{command}")

          status.output = stdout.readlines
          BigBlueButton.logger.info( "Output: #{Array(status.output).join()} ") unless status.output.empty?
   
          status.errors = stderr.readlines
          unless status.errors.empty?
            BigBlueButton.logger.error( "Error: stderr: #{Array(status.errors).join()}")
          end
        rescue SignalException => e
          BigBlueButton.logger.info "[#{$$}] Received signal (#{e.signo} #{e.signm}) in Open4 block"

          BigBlueButton.logger.info "Sending signal to the child process"
          Process.kill( e.signm.sub(/SIG/, ''), pid)
        end
    end
    BigBlueButton.logger.info("Process exited? #{status.exited?}")
    if status.exited?
      BigBlueButton.logger.info("Success?: #{status.success?}")
      BigBlueButton.logger.info("Exit status: #{status.exitstatus}")
      if status.success? == false and fail_on_error
        raise "Execution failed"
      end
    end
    status
  end

  def self.exec_ret(*command)
    BigBlueButton.logger.info "Executing: #{command.join(' ')}"
    IO.popen([*command, :err => [:child, :out]]) do |io|
      io.lines.each do |line|
        BigBlueButton.logger.info line.chomp
      end
    end
    BigBlueButton.logger.info "Exit status: #{$?.exitstatus}"
    return $?.exitstatus
  end

  def self.exec_redirect_ret(outio, *command)
    BigBlueButton.logger.info "Executing: #{command.join(' ')}"
    BigBlueButton.logger.info "Sending output to #{outio}"
    IO.pipe do |r, w|
      pid = spawn(*command, :out => outio, :err => w)
      w.close
      r.lines.each do |line|
        BigBlueButton.logger.info line.chomp
      end
      Process.waitpid(pid)
      BigBlueButton.logger.info "Exit status: #{$?.exitstatus}"
      return $?.exitstatus
    end
  end

  def self.hash_to_str(hash)
    return PP.pp(hash, "")
  end

  def self.monotonic_clock()
    return (AbsoluteTime.now * 1000).to_i
  end

  def self.download(url, output)
    BigBlueButton.logger.info "Downloading #{url} to #{output}"

    uri = URI.parse(url)
    if ["http", "https", "ftp"].include? uri.scheme
      command = "wget -q --spider #{url}"
      BigBlueButton.execute(command)
    end

    if uri.scheme.nil?
      url = "file://" + url
    end

    command = "curl --output #{output} #{url}"
    BigBlueButton.execute(command)
  end

  def self.try_download(url, output)
    begin
      self.download(url, output)
    rescue Exception => e
      BigBlueButton.logger.error "Failed to download file: #{e.to_s}"
      FileUtils.rm_f output
    end
  end
  
end
