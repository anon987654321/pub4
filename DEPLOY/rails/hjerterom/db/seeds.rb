admin = User.find_or_create_by!(email_address: "admin@hjerterom.no") do |u|
  u.password = u.password_confirmation = "password123"
end

crisis_lines = [
  { title: "Mental Helse Hjelpelinjen", phone: "116 123", available_24h: true, languages: "Norsk", country: "NO" },
  { title: "Kirkens SOS", phone: "22 40 00 40", available_24h: true, languages: "Norsk", country: "NO" },
  { title: "Røde Kors Besøkstjeneste", phone: "800 33 321", available_24h: false, languages: "Norsk", country: "NO" },
]
crisis_lines.each { |c| Crisis.find_or_create_by!(title: c[:title]) { |cr| cr.update(c) } }

cats = [
  { name: "Angst",     slug: "angst",    type_of: "mental_health" },
  { name: "Depresjon", slug: "depresjon", type_of: "mental_health" },
  { name: "Ensomhet",  slug: "ensomhet",  type_of: "mental_health" },
  { name: "Mat",       slug: "mat",       type_of: "food" },
]
cats.each { |c| Category.find_or_create_by!(slug: c[:slug]) { |cat| cat.update(c) } }

puts "Seeded crisis lines and categories"
