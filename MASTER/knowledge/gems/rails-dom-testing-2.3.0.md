assert_dom(html, 'h1', 'Lingua Francia')
assert_dom(root.at('.hello'), '.goodbye')
refute_dom(root.at('.hello'), '.goodbye')
