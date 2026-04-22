# Load both parsers (default)
require "crack"

# Load only the JSON parser (faster start‑up if XML isn’t needed)
require "crack/json"

# Load only the XML parser (useful when you only work with XML)
require "crack/xml"
