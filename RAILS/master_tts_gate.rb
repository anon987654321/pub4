#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "gates/lib/master_tts_gate"

Deploy::MasterTtsGate.run.report!("MASTER TTS gate passed.")
