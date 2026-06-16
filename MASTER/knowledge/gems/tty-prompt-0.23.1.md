# frozen_string_literal: true

require "tty-prompt"

# Create a reusable prompt instance.
prompt = TTY::Prompt.new

# Example: ask the user to select an option.
choice = prompt.select("Pick a fruit:", %w[Apple Banana Cherry])

puts "You chose: #{choice}"
