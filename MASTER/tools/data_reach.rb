#!/usr/bin/env ruby
# frozen_string_literal: true

# Compatibility entrypoint. The canonical implementation lives in audit/.
target = File.expand_path("audit/data_reach.rb", __dir__)
if File.expand_path($PROGRAM_NAME) == File.expand_path(__FILE__)
  previous_program_name = $PROGRAM_NAME
  $PROGRAM_NAME = target
  begin
    load target
  ensure
    $PROGRAM_NAME = previous_program_name
  end
else
  require_relative "audit/data_reach"
end
