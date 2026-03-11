# frozen_string_literal: true

require "minitest/autorun"

require_relative "../lib/master3/result"
require_relative "../lib/master3/pipeline"
require_relative "../lib/master3/ring_buffer"
require_relative "../lib/master3/event_bus"
require_relative "../lib/master3/logging"
require_relative "../lib/master3/stages/intake"
require_relative "../lib/master3/stages/route"
require_relative "../lib/master3/stages/guard"
require_relative "../lib/master3/stages/execute"
require_relative "../lib/master3/stages/strunk"
require_relative "../lib/master3/stages/render"
