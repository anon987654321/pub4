# frozen_string_literal: true

module Brgen
  # Realistic Bergen / r/bergen-inspired demo content for brgen.no (Tradedoubler, demos).
  # Norwegian copy, local handles, staggered timestamps, optional picsum attachments.
  class BergenDemoSeeder
    USERS = [
      %w[Emilie emilie_floyen],
      %w[Henrik henrik_vestland],
      %w[Kari kari_bybanen],
      %w[Ola ola_nordnes],
      %w[Ingrid ingrid_ulriken],
      %w[Magnus magnus_student],
      %w[Sofie sofie_regnby],
      %w[Anders anders_fisketorget],
      %w[Marte marte_kode24],
      %w[Jonas jonas_7fjell],
      %w[Hanne hanne_sandviken],
      %w[Per per_laksevag],
      %w[Silje silje_korall],
      %w[Torbjørn tor_fana],
      %w[Live live_bergenlive]
    ].freeze

    POSTS = [
      {
        user: "emilie_floyen", community: "bergen", hours_ago: 2,
        title: "Sol på Fløyen — verdt hele turen",
        content: "Tok Fløibanen opp før jobb. Utsikten over Vågen var helt vill i morgensola. Anbefaler å komme før kl 09 hvis dere vil unngå kø.",
        image: "bergen-floyen-morning", comments: [
          "Var der i går! Magisk.",
          "Husk varm jakke på toppen, blåser alltid."
        ]
      },
      {
        user: "henrik_vestland", community: "bergen", hours_ago: 5,
        title: "Regnværsdag på Bryggen",
        content: "Sitter på Kaffebrenneriet og hører regnet mot taket. Hvor er favorittstedet deres når det øser ned?",
        image: "bergen-bryggen-rain", comments: [
          "Dampen på Torget, alltid.",
          "Biblioteket + kaffe fra Godt Brød."
        ]
      },
      {
        user: "kari_bybanen", community: "norge", hours_ago: 8,
        title: "Bybanen forsinket igjen?",
        content: "Står på Florida og det kommer ingen avgang mot sentrum. Noen som vet om det er signalfeil?",
        comments: [
          "Ja, meldt på Skyss-appen nå.",
          "Ta buss 12 som backup hvis du har det travelt."
        ]
      },
      {
        user: "ola_nordnes", community: "mat", hours_ago: 11,
        title: "Beste kanelbolle i sentrum?",
        content: "Jeg sverger til Baker Hansen, men kollegaen mener Godt Brød er bedre. Hva stemmer folket for?",
        image: "bergen-bakery", comments: [
          "Baker Hansen når de er ferske.",
          "Colonialen på Nordnes er undervurdert."
        ]
      },
      {
        user: "ingrid_ulriken", community: "bergen", hours_ago: 14,
        title: "Ulriken i kveld — hvem blir med?",
        content: "Planlegger tur opp Ulriken rundt 18. Rolig tempo, kanskje mat på toppen. DM om du vil henge.",
        image: "bergen-ulriken-trail", comments: [
          "Er med! Har ekstra hodelykt.",
          "Sjekk værmeldingen først, skyer ruller inn fort."
        ]
      },
      {
        user: "magnus_student", community: "bergen", hours_ago: 18,
        title: "UiB-eksamen og ingen plass på biblioteket",
        content: "Alle plassene på HF-bib er borte. Tips til stille leseplasser i sentrum etter kl 16?",
        comments: [
          "Studentersamfunnet, øverste etasje.",
          "KODE café hvis du tåler litt bakgrunnsstøy."
        ]
      },
      {
        user: "sofie_regnby", community: "kultur", hours_ago: 22,
        title: "Grieghallen i helgen",
        content: "Skal på Beethoven med Bergen Filharmoniske. Har noen vært der nylig — hvor tidlig bør man være inne?",
        image: "bergen-concert-hall", comments: [
          "30 min før er plenty.",
          "Husk at garderoben kan ta tid på fulle dager."
        ]
      },
      {
        user: "anders_fisketorget", community: "mat", hours_ago: 26,
        title: "Fisketorget lørdag — hva kjøper dere?",
        content: "Reker, blåskjell og litt laks hver gang. Finnes det noe lokalt jeg alltid overser?",
        image: "bergen-fish-market", comments: [
          "Kveite om de har det.",
          "Spør om hummersuppe-restene, billig og godt."
        ]
      },
      {
        user: "marte_kode24", community: "bergen", hours_ago: 30,
        title: "Tech-meetup på Mesh?",
        content: "Så at det er meetup på Mesh neste uke. Noen her som har vært — er det mer mingling eller foredrag?",
        comments: [
          "Begge deler, avslappet stemning.",
          "Ta med ladekabel, sitteplassene fylles fort."
        ]
      },
      {
        user: "jonas_7fjell", community: "bergen", hours_ago: 36,
        title: "Løypeforslag for 7-fjellsturen",
        content: "Skal endelig ta 7-fjellsturen i sommer. Vil gjerne dele etappen i to dager — har dere en favorittrute?",
        image: "bergen-hiking", comments: [
          "Dag 1: Fløyen–Rundemanen, dag 2: resten.",
          "Husk nok vann mellom Lyderhorn og Damsgårdsfjellet."
        ]
      },
      {
        user: "hanne_sandviken", community: "norge", hours_ago: 42,
        title: "Barnehageplass i Bergen — realistisk ventetid?",
        content: "Flytter til Sandviken til høsten. Hva er erfaringen deres med ventelister i bydelen?",
        comments: [
          "Var 4 måneder for oss, avhengig av bydel.",
          "Søk tidlig og følg opp med kommunen."
        ]
      },
      {
        user: "per_laksevag", community: "bergen", hours_ago: 48,
        title: "Nye sykkelstier langs Store Lungegårdsvann",
        content: "Syklet rundt vannet i går kveld. Nye lys gjør det mye tryggere. Håper de fortsetter mot Puddefjorden.",
        image: "bergen-lungegaardsvann", comments: [
          "Enig, stor forbedring.",
          "Fortsatt litt glatt ved regn, ta det rolig i svingene."
        ]
      },
      {
        user: "silje_korall", community: "musikk", hours_ago: 54,
        title: "Bergenfest — hvilke artister satser dere på?",
        content: "Lineup er ute og jeg klarer ikke velge én dag. Hvem er must-see i år?",
        comments: [
          "Fredagskvelden ser sterk ut.",
          "Kom tidlig for parken, det blir folksomt."
        ]
      },
      {
        user: "tor_fana", community: "bergen", hours_ago: 60,
        title: "Vannlekkasje i leilighet — hva gjør man først?",
        content: "Vann fra taket i Fana i natt. Har dokumentert og ringt utleier. Noe mer jeg bør gjøre med en gang?",
        comments: [
          "Ta bilder av alt, også inventar.",
          "Meld til forsikring samme dag."
        ]
      },
      {
        user: "live_bergenlive", community: "kultur", hours_ago: 68,
        title: "Standup på Logen denne uken",
        content: "Noen som har vært på open mic der? Tenker å teste en kort settliste.",
        image: "bergen-logen", comments: [
          "Hyggelig publikum, kom tidlig.",
          "Book plass, det er begrenset kapasitet."
        ]
      },
      {
        user: "emilie_floyen", community: "bergen", hours_ago: 80, anonymous: true,
        title: "Anonym: nattbuss etter sentrum?",
        content: "Jobber sent på hverdager. Er nattbussene fortsatt upålitelige etter midnatt, eller har det blitt bedre?",
        comments: [
          "Bedre etter ruteendring, men sjekk Boreal-app.",
          "Skyss natt viser sanntid nå."
        ]
      },
      {
        user: "henrik_vestland", community: "mat", hours_ago: 96,
        title: "Pizza på Nordnes — Deli eller Bella?",
        content: "Klassisk fredagskrangel i kollektivet. Hva vinner i Bergen akkurat nå?",
        comments: [
          "Deli for tynn bunn.",
          "Bella når man vil ha storfamilie-porsjoner."
        ]
      },
      {
        user: "kari_bybanen", community: "bergen", hours_ago: 120,
        title: "Tåk over Vågen i dag",
        content: "Gikk over Bryggen i tjukk tåke — føltes som en annen by. Tok noen bilder hvis noen vil ha wallpaper.",
        image: "bergen-fog-vagen", comments: [
          "Legg ut!",
          "Perfekt stemning for svart/hvitt."
        ]
      },
      {
        user: "ola_nordnes", community: "norge", hours_ago: 140,
        title: "Boligpriser i Bergen — fortsatt helt sprøtt?",
        content: "Ser på 2-roms i Møhlenpris. Er det noen som faktisk har kjøpt nylig uten å vinne arv-lotteriet?",
        comments: [
          "Møhlenpris holder seg høyt, sjekk borettslag vs. eier.",
          "Vurder Laksevåg hvis du vil ha bedre kvm-pris."
        ]
      },
      {
        user: "ingrid_ulriken", community: "bergen", hours_ago: 168,
        title: "Hundepark anbefalinger?",
        content: "Ny hund i familien. Hvor i Bergen er det best å slippe den løs uten å måtte kjøre 40 min?",
        image: "bergen-dog-park", comments: [
          "Nordnesparken tidlig morgen.",
          "Fana fjellstier hvis den tåler mer aktivitet."
        ]
      }
    ].freeze

    LISTINGS = [
      { user: "anders_fisketorget", title: "Brukt sykkel — Bergen sentrum", price_cents: 3_500_00, image: "bergen-bike-sale" },
      { user: "marte_kode24", title: "MacBook Air M1, pent brukt", price_cents: 6_500_00, image: "bergen-macbook" },
      { user: "tor_fana", title: "IKEA sofa, hentes Fana", price_cents: 2_000_00, image: "bergen-sofa" },
      { user: "hanne_sandviken", title: "Barnevogn, god stand", price_cents: 1_800_00, image: "bergen-stroller" },
      { user: "per_laksevag", title: "Telemarkski + støvler", price_cents: 2_400_00, image: "bergen-skis" }
    ].freeze

    DATING_BIOS = [
      { user: "emilie_floyen", bio: "Kaffe, fjelltur og altfor mange bøker. Leter etter noen som tåler regn.", age: 28, bydel: "Nordnes", image: "bergen-dating-1" },
      { user: "magnus_student", bio: "UiB, spiller gitar dårlig men med god energi. Mat på Fisketorget er første date.", age: 24, bydel: "Sentrum", image: "bergen-dating-2" },
      { user: "silje_korall", bio: "Jobber med design, elsker konserter og spontane båtturer.", age: 31, bydel: "Sandviken", image: "bergen-dating-3" },
      { user: "jonas_7fjell", bio: "Løper stier, lager middag hjemme, savner sol fra Østlandet.", age: 33, bydel: "Kalfaret", image: "bergen-dating-4" }
    ].freeze

    def initialize(city, attach_media: !DemoMedia.skip_attach?)
      @city = city
      @attach_media = attach_media
      @users_by_username = {}
    end

    def seed!
      ActsAsTenant.with_tenant(@city) do
        communities = ensure_communities
        seed_users
        seed_posts(communities)
        seed_listings
        seed_dating
      end
    end

    private

    def ensure_communities
      admin = User.strict_loading(false).find_or_create_by!(email_address: "admin@#{@city.domain}") do |user|
        user.username = "admin_#{@city.slug}"
        user.password = user.password_confirmation = "password123"
        user.city = @city
      end

      Brgen::CityContent.community_slugs_for(@city.country_code).index_with do |slug|
        Community.find_or_create_by!(slug: slug, city: @city) do |community|
          community.name = slug.capitalize
          community.description = "#{@city.name} — #{slug}"
          community.user = admin
        end
      end
    end

    def seed_users
      USERS.each do |first_name, username|
        @users_by_username[username] = User.strict_loading(false).find_or_create_by!(
          email_address: "#{username}@#{@city.domain}"
        ) do |user|
          user.username = username
          user.password = user.password_confirmation = "password123"
          user.city = @city
          user.latitude = @city.latitude.to_f + rand(-0.04..0.04)
          user.longitude = @city.longitude.to_f + rand(-0.04..0.04)
        end
      end
    end

    def seed_posts(communities)
      POSTS.each do |row|
        user = @users_by_username.fetch(row[:user])
        community = communities.fetch(row[:community])

        post = Post.create!(
          user: user,
          city: @city,
          community: community,
          title: row[:title],
          content: row[:content],
          anonymous: row[:anonymous] == true,
          created_at: row[:hours_ago].hours.ago + rand(0..45).minutes
        )
        post.record_activity!("BergenDemoSeed") if post.respond_to?(:record_activity!)

        DemoMedia.attach_remote!(post, :image, seed: row[:image]) if @attach_media && row[:image]

        Array(row[:comments]).each_with_index do |body, index|
          commenter = @users_by_username.values.sample
          Comment.create!(
            user: commenter,
            commentable: post,
            content: body,
            created_at: post.created_at + (index + 1).minutes + rand(10..90).seconds
          )
        end

        voter = @users_by_username.values.sample
        post.reactions.find_or_create_by!(user: voter, kind: %w[like love].sample)
        post.votes.find_or_create_by!(user: @users_by_username.values.sample) { |vote| vote.value = 1 }
      end
    end

    def seed_listings
      category = Marketplace::Category.first || Marketplace::Category.create!(name: "Diverse", slug: "diverse-bergen")

      LISTINGS.each do |row|
        user = @users_by_username.fetch(row[:user])
        listing = Marketplace::Listing.create!(
          user: user,
          title: row[:title],
          description: "Hentes i #{@city.name}. PM for detaljer.",
          price_cents: row[:price_cents],
          category: category,
          location: @city.name,
          status: "active",
          created_at: rand(2..21).days.ago
        )
        DemoMedia.attach_remote!(listing, :photos, seed: row[:image]) if @attach_media
      end
    end

    def seed_dating
      DATING_BIOS.each do |row|
        user = @users_by_username.fetch(row[:user])
        profile = Dating::Profile.find_or_initialize_by(user: user)
        profile.assign_attributes(
          bio: row[:bio],
          age: row[:age],
          gender: Dating::Profile::GENDERS.sample,
          looking_for: Dating::Profile::LOOKING_FOR.sample,
          latitude: user.latitude,
          longitude: user.longitude,
          bydel: row[:bydel],
          visible: false
        )
        DemoMedia.attach_remote!(profile, :photos, seed: row[:image], width: 600, height: 900) if @attach_media
        profile.visible = true
        profile.save!
      end
    end
  end
end