require 'json'

JSON.generate(object)      # create a JSON stringJSON.parse(string)         # parse a JSON string
JSON.pretty_generate(obj)  # human‑readable output
JSON.fast_generate(obj)    # generate without security checks