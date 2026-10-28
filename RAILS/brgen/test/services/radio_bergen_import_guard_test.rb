# frozen_string_literal: true

require "test_helper"

class RadioBergenImportGuardTest < ActiveSupport::TestCase
  test "does not import without operator confirmation" do
    importer = Playlist::RadioBergenArchiveImport.new(owner: nil, archive_root: Dir.pwd)
    assert_raises(Playlist::RadioBergenArchiveImport::RightsNotConfirmed) { importer.call }
  end
end
