# frozen_string_literal: true

require "test_helper"

class ImagePresenterTest < ActiveSupport::TestCase
  PNG = "\x89PNG\r\n\x1A\n".b + ("\0".b * 64)

  def upload
    Rack::Test::UploadedFile.new(StringIO.new(PNG), "image/png", true, original_filename: "face.png")
  end

  # /chat/photo is open to visitors; only an operator's upload runs postpro.
  test "a visitor's photo is stored as uploaded and postpro never starts" do
    presenter = ImagePresenter.new(process: false)
    ran = false
    presenter.define_singleton_method(:postpro_photo) { |*| ran = true }

    status, payload = presenter.store(upload)

    assert_equal :ok, status
    assert_equal false, payload[:processed]
    refute ran
  end

  test "a grade that outlives its limit is killed, not waited for" do
    presenter = ImagePresenter.new
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    _out, status = presenter.send(:run_bounded, [RbConfig.ruby, "-e", "sleep 30"], chdir: Dir.tmpdir, timeout_s: 1)

    assert_nil status
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 10
  end
end
