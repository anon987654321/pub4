require "base64"

encoded = Base64.encode64("Send reinforcements")
# => "U2VuZCByZWluZm9yY2VtZW50cw=\n"

decoded = Base64.decode64(encoded)
# => "Send reinforcements"
