#!/usr/bin/env ruby
# frozen_string_literal: true

# Thin executable shell; instruments, effects and composition logic live under lib/.
require_relative 'lib/dilla'

run(ARGV) if $PROGRAM_NAME == __FILE__
