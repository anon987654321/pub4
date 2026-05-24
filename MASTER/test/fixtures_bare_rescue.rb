# frozen_string_literal: true

module TestFixture
  def risky_read
    File.read("/tmp/x")
  rescue StandardError
    nil
  end
end
