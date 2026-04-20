require "test/unit"
require "rack/test"
require "json"

class HomepageTest < Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    ->(env) { [200, {'content-type' => 'text/plain'}, ['All responses are OK']] }
  end

  def test_response_is_ok
    # optionally set headers used for all requests in this spec:
    # header 'accept-charset', 'utf-8'
    get '/'
    assert last_response.ok?
    assert_equal 'All responses are OK', last_response.body
  end

  def delete_with_url_params_and_body
    delete '/?foo=bar', JSON.generate('baz' => 'zot')
  end

  def post_with_json
    post uri, JSON.generate('baz' => 'zot'), 'CONTENT_TYPE' => 'application/json'
  end
end
