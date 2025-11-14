#!/usr/bin/env ruby
# frozen_string_literal: true

# Postpro.rb - Professional Cinematic Post-Processing
# Version: 15.0.0 - Modular Architecture (master.json compliant)

require "logger"
require "json"
require "time"
require "fileutils"

require_relative "__shared/@bootstrap"
require_relative "__shared/@fx_core"
require_relative "__shared/@fx_creative"
require_relative "__shared/@cli"

BOOTSTRAP = PostproBootstrap.run
$logger = Logger.new("postpro.log", "daily", level: Logger::DEBUG)
$cli_logger = Logger.new(STDOUT, level: Logger::INFO)

if BOOTSTRAP[:gems][:tty]
  require "tty-prompt"
  PROMPT = TTY::Prompt.new
else
  PROMPT = nil
end

if BOOTSTRAP[:gems][:vips]
  require "vips"
end

CAMERA_PROFILES = BOOTSTRAP[:camera_profiles]
CONFIG = BOOTSTRAP[:config]

auto_launch if __FILE__ == $0
