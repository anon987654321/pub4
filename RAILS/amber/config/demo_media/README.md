# Demo media

**The demo wardrobe should show the cloth as well as the cut, so a visitor sees both the shape a
piece takes on the figure and the fabric it is made of.** Each photograph here is one garment or
one outfit laid flat on a single warm backdrop, with no person in the frame, so the clothes are
the only thing that changes from one picture to the next.

The catalogue is default.yml, and it maps a seed key to a file in the images folder beside it.
Today it holds one row, the camel wrap coat. The prompts for seventeen garments and three
outfits are written in STUDIO/replicate/lora/seed_media.yml and the other nineteen are not yet
rendered and filed, so most demo items still show only the drawn cut-out. Filing a frame is
enough: the next seed attaches it, and no code changes.

The seeder attaches the drawn cut-out first and the photograph second. The dressing room lays
its zones over the first photo, and the cut-out is drawn for that. The item page shows every
photo, which is where the flat lay earns its place. A key the catalogue does not hold attaches
nothing, and a row whose file is missing is skipped with a warning rather than raised, since one
failed seed blocks every deploy. Setting SKIP_DEMO_MEDIA turns attachment off, and the test
environment never attaches.

The frames are rendered on Replicate and graded by postpro before they arrive here.
install_seed_media.rb in STUDIO/replicate/lora/_toolkit files them, and the prompt, model, seed
and preset of each render are recorded in STUDIO/replicate/lora/seed_media_manifest.yml.

These graded copies are tracked in git, which is a deliberate exception to the rule against
committing generated assets. That rule keeps build output and renders out of history because
they can be made again from source. These cannot: a render costs money and never comes out the
same twice, and the deploy copies only tracked files to the box, where the seeds read them. So
the app keeps a small copy, and the full renders stay out of git on the machine that made them.
