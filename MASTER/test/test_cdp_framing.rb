# frozen_string_literal: true

require_relative "test_helper"
require "socket"
require File.expand_path("../gates/support/cdp_session", __dir__)

# The WebSocket reader against scripted server frames, with no browser. The
# 127-byte case is the one that desynchronised a real brgen review: a frame
# whose 16-bit length is exactly 127 was read as if it had a 64-bit length.
class TestCdpFraming < Minitest::Test
  class Reader
    include Deploy::CdpFraming

    def initialize(socket)
      @socket = socket
      @mid_frame = false
    end

    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    def message(timeout = 2) = read_frame(timeout)
  end

  def frame(payload, opcode: 0x1, fin: true)
    head = [(fin ? 0x80 : 0) | opcode].pack("C")
    len = payload.bytesize
    head + if len < 126 then [len].pack("C")
           elsif len < 65_536 then [126, len].pack("Cn")
           else [127, len].pack("CQ>")
           end + payload
  end

  def read_back(*frames)
    server, client = UNIXSocket.pair
    writer = Thread.new { server.write(frames.join) }
    reader = Reader.new(client)
    yield reader
    writer.join
  ensure
    server&.close
    client&.close
  end

  def test_a_126_form_frame_of_exactly_127_bytes_is_read_whole
    payload = "x" * 127
    read_back(frame(payload), frame("after")) do |reader|
      assert_equal payload, reader.message
      assert_equal "after", reader.message
    end
  end

  def test_lengths_around_every_header_form_boundary
    [0, 1, 125, 126, 127, 128, 255, 256, 65_535, 65_536, 70_000].each do |size|
      payload = "a" * size
      read_back(frame(payload), frame("next")) do |reader|
        assert_equal payload, reader.message, "length #{size}"
        assert_equal "next", reader.message, "length #{size} left the stream out of step"
      end
    end
  end

  def test_fragmented_message_with_a_ping_between_fragments
    read_back(frame("hel", fin: false), frame("", opcode: 0x9), frame("lo", opcode: 0x0)) do |reader|
      assert_equal "hello", reader.message
    end
  end
end
