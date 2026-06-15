# frozen_string_literal: true

# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Multi-tradition scripture data for improved comparisons & visualizations (Wave 1 baibl enhancement)
# Bible, Quran, Bhagavad Gita + thematic cross-references for parallel views and viz.

# Clear for replant (dev)
[CrossReference, Verse, Chapter, Book].each(&:delete_all)

# === BIBLE (tradition: bible) ===
genesis = Book.create!(name: "Genesis", abbreviation: "Gen", tradition: "bible", order_index: 1)
john    = Book.create!(name: "John", abbreviation: "Jn", tradition: "bible", order_index: 43)

gen_ch1 = genesis.chapters.create!(number: 1)
gen_ch1.verses.create!(number: 1, content: "In the beginning God created the heavens and the earth.")
gen_ch1.verses.create!(number: 3, content: "And God said, Let there be light: and there was light.")
gen_ch1.verses.create!(number: 27, content: "So God created man in his own image, in the image of God created he him; male and female created he them.")

jn_ch3 = john.chapters.create!(number: 3)
jn_ch3.verses.create!(number: 16, content: "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.")
jn_ch3.verses.create!(number: 17, content: "For God sent not his Son into the world to condemn the world; but that the world through him might be saved.")

# === QURAN (tradition: quran) — Surahs as "books" for navigation simplicity ===
fatiha = Book.create!(name: "Al-Fatiha", abbreviation: "Fatiha", tradition: "quran", order_index: 100)
baqara = Book.create!(name: "Al-Baqarah", abbreviation: "Baqarah", tradition: "quran", order_index: 101)

fatiha_ch = fatiha.chapters.create!(number: 1)
fatiha_ch.verses.create!(number: 1, content: "In the name of Allah, the Most Gracious, the Most Merciful.")
fatiha_ch.verses.create!(number: 2, content: "All praise is for Allah—Lord of all worlds.")
fatiha_ch.verses.create!(number: 5, content: "You alone we worship and You alone we ask for help.")

baqara_ch2 = baqara.chapters.create!(number: 2)
baqara_ch2.verses.create!(number: 255, content: "Allah! There is no god but He, the Living, the Self-Subsisting, Eternal.")
baqara_ch2.verses.create!(number: 256, content: "Let there be no compulsion in religion.")

# === BHAGAVAD GITA (tradition: gita) ===
gita = Book.create!(name: "Bhagavad Gita", abbreviation: "Gita", tradition: "gita", order_index: 200)
gita_ch2 = gita.chapters.create!(number: 2)
gita_ch2.verses.create!(number: 47, content: "You have a right to perform your prescribed duties, but you are not entitled to the fruits of your actions.")
gita_ch2.verses.create!(number: 48, content: "Perform your duty equipoised, O Arjuna, abandoning all attachment to success or failure. Such equanimity is called yoga.")

gita_ch18 = gita.chapters.create!(number: 18)
gita_ch18.verses.create!(number: 66, content: "Abandon all varieties of dharma and just surrender unto Me. I shall deliver you from all sinful reactions. Do not fear.")

# === Thematic cross-references for comparisons (links across traditions) ===
# Creation theme
CrossReference.create!(verse: Verse.find_by(content: /In the beginning God created/), target_verse: Verse.find_by(content: /In the name of Allah/), kind: "thematic")
CrossReference.create!(verse: Verse.find_by(content: /In the beginning God created/), target_verse: Verse.find_by(content: /You have a right to perform/), kind: "thematic") # loose for demo

# Love / compassion
CrossReference.create!(verse: Verse.find_by(content: /For God so loved the world/), target_verse: Verse.find_by(content: /All praise is for Allah/), kind: "thematic")
CrossReference.create!(verse: Verse.find_by(content: /For God so loved the world/), target_verse: Verse.find_by(content: /Abandon all varieties of dharma/), kind: "parallel")

# Duty / submission
CrossReference.create!(verse: Verse.find_by(content: /You have a right to perform/), target_verse: Verse.find_by(content: /Let there be no compulsion/), kind: "thematic")

puts "baibl multi-tradition seeds complete: Bible, Quran, Bhagavad Gita + cross-theme links for comparisons & viz."
