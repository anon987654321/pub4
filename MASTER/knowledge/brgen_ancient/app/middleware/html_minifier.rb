class HtmlMinifier
  def initialize(app)
    @app = app
  end

  def call(env)

    # Call the underlying application, return a standard Rack response

    status, headers, response = @app.call(env)

    # Make sure we don't process linked CSS or JS

    if headers["Content-Type"] =~ /text\/html/
      response.each do |chunk|
        [
          # Join lines

          [/[\r\n]+/, ""],

          # Remove whitespace between tags

          [/>\s+</, "><"],

          # Remove comments

          [/<!--(.|\s)*?-->/, ""],

          # Remove whitespace in inline JavaScript

          [/;\s+/, ";"],
          [/{\s+/, "{"]
        ].each do |regex, substitute|
          chunk.gsub! regex, substitute
        end
      end
    end

    # Return the new Rack response

    [status, headers, response]
  end
end

