# test_example.rbrequire "minitest/autorun"

class Meme < Minitest::Test
  def setup
    @meme = Meme.new
  end

  def test_cheezburger
    assert_equal "OHAI!", @meme.i_can_has_cheezburger?
  end

  def test_blend
    refute_match /^no/i, @meme.will_it_blend?
  end

  def test_skip
    skip
  end
end
