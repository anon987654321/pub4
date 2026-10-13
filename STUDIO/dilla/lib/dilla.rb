# frozen_string_literal: true

require 'json'
require 'optparse'
require 'fileutils'
require 'zlib'
require 'shellwords'

SAMPLE_RATE = 44_100
MAX_OFFSET = 0.035
NYQUIST_SHARE = 0.45
MAX_DETUNE = 0.0035
AUDIBLE_TOP_HZ = 14_000.0

require_relative 'dilla/wav'
require_relative 'dilla/chords'
require_relative 'dilla/synthesis'
require_relative 'dilla/voices'
require_relative 'dilla/colour'
require_relative 'dilla/tape'
require_relative 'dilla/drums'
require_relative 'dilla/percussion'
require_relative 'dilla/effects'
require_relative 'dilla/echo'
require_relative 'dilla/arp'
require_relative 'dilla/sequencer'
require_relative 'dilla/midi'
require_relative 'dilla/playlist'
require_relative 'dilla/engine'
