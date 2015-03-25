#!/usr/bin/ruby
# Set encoding to utf-8
# encoding: UTF-8

require 'rubygems'
require 'daemons'

# http://stackoverflow.com/a/1563811/1006288
Daemons.run 'mconf-presentation-recorder-worker.rb',
    :dir      => '/tmp',
    :dir_mode => :normal
