#!/usr/bin/env ruby
# frozen_string_literal: true

# demo.rb — the catalogue showcase, demo.wav.
# The engine stays dilla.rb. This file is the take.
Dir.chdir(__dir__)
exec(RbConfig.ruby, File.join(__dir__, "dilla.rb"), *ARGV)
