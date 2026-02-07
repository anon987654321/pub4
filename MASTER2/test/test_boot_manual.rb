#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script to verify boot.rb functionality

require_relative "../lib/master"

# Setup database
MASTER::DB.setup(path: ":memory:")

# Call the boot sequence
MASTER::Boot.banner
