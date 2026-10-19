# What makes a good photograph

Researched 2026-10-19 from the sources linked inline. A rule marked (unverified) rests on
one thin source and needs a test frame before a tool relies on it. The look itself,
meaning colour, grain and mood, belongs to the operator; this guide holds checks and
facts, and no default value.

## Light and the face

Light direction decides a portrait before gear does. Seat the subject sideways to a
window so one side of the face is bright and the other holds shadow; overcast sky gives
soft, even light when no window is available.
[Photoworkout](https://www.photoworkout.com/portrait-photography-lighting/),
[Digital Photography School](https://digital-photography-school.com/6-tips-for-taking-better-natural-light-classic-portraits/)

Eyes need a catchlight. A round one marks a large soft source, a sharp point a small
hard one. A frame without it reads dead, and a turn of the head restores it.

Hard flash and "unflattering" light are a deliberate style, not a default. The warp set
in `ideas.yml` asks for them on purpose; a likeness test uses the flattering sets.

## Lens, distance and distortion

Portraits sit between 50 and 85 mm on full frame, with the camera about two metres
from the face. A wide lens close to the face enlarges the nose and shrinks the ears, and
a generator copies that distortion from its references.
[Tamron](https://www.tamron.com/global/consumer/sp/impression/detail/article-how-to-take-portrait-pictures.html)

Phone selfies are the weakest reference for this reason. A reference made at 50 to 85 mm
beats three made at arm's length.

## Frame and moment

Cartier-Bresson treated composition as simultaneous with the exposure: elements balance
inside movement for one instant, and a head moved a fraction of a millimetre changes the
lines. [MoMA, 1968](https://www.moma.org/docs/press_archives/4017/releases/MOMA_1968_Jan-June_0033_33.pdf)

Szarkowski named five choices in *The Photographer's Eye*: the thing itself, the detail,
the frame, time and vantage point. The frame is a decision about what to leave out.
[Falmouth summary](https://journal.falmouth.ac.uk/broughttolight/?p=12) (secondary; check
the book)

Avedon removed context: white ground, frontal pose, direct gaze, nothing competing with
the face. [Fraenkel Gallery](https://fraenkelgallery.com/shop/portraits)

Expression reads best when natural. Forced smiles and overacting fail in every source.

## Grade

Order of work: fix exposure and contrast, set white balance and tint, then raise
saturation. Check skin on a vectorscope, where skin of every complexion falls along the
red-yellow line, and sample bare skin, because make-up skews the reading. Dramatic light
moves skin off the line on purpose.
[Larry Jordan](https://larryjordan.com/articles/the-secret-to-setting-skin-colors-accurately/)

Teal in the shadows against orange skin separates a subject through complementary
colour. Weak exposure and low saturation leave the look nothing to work with, and the
sources advise a light hand.
[PetaPixel](https://petapixel.com/2017/02/23/orange-teal-look-popular-hollywood/)

## Checks for our renders

- Identity: a render passes only when its face similarity to the subject's references
  clears a threshold set from those references. The operator reviews survivors at full
  size, never on a contact sheet. (A tool for this does not exist yet.)
- Light: the prompt names a direction and a source, and the frame shows catchlights.
- Lens: the prompt names a focal length between 50 and 85 mm and a distance.
- Grade: exposure and white balance first, skin on the scope, one grade for the whole
  piece. Random chains are exploration, not delivery.
- Spend: one test frame, reviewed full size, before any batch.
- Candidates: `MASS_GENERATE_CURATE` applies. Render several materially different
  candidates per shot, discard by the identity check, and let the operator choose; the
  first plausible frame is a draft.

## Not verified

Nothing found on Leibovitz, on halation, grain and tone-curve principles, or on
Szarkowski beyond secondary summaries. The vectorscope reference values in
Van Hurkman's *Color Grading Handbook* need the book itself.
