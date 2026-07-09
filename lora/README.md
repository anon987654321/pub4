# Ragnhild LoRA og analoge portrettnotater

Dette er det lille verkstedet der Ragnhild-portrettprosjektet bor.

Kortversjonen: de ferdige profilbildene akkurat na er ikke falske nye ansikter funnet opp av en modell. De er kildebaserte portretter laget fra ekte bilderammer av Ragnhild, deretter beskjart, balansert og fargegradert med et varsomt analogt fotouttrykk. Malet var ikke a gjore henne om til en blank, syntetisk fremmed. Malet var a bevare henne som seg selv: norsk, voksen, varm, naturlig, en kvinne i 40-arene med ekte uttrykk, ekte hudtekstur og lys som ikke overdøver personen.

## Det som finnes na

Det ferdige kildebaserte profilsettet ligger her:

`training/ragnhild/ai_toolkit/output/ragnhild_v2/profile_set/final`

Kontaktarket for rask gjennomgang ligger her:

`training/ragnhild/ai_toolkit/output/ragnhild_v2/profile_set/final/ragnhild_final_contact.jpg`

Disse bildene er laget fra utvalgte ekte Ragnhild-bilder, hovedsakelig de rammene som best bevarer identiteten hennes i treningssettet. De er ikke produsert av en ferdig FLUX LoRA-genereringsrunde. Den forskjellen er viktig. Nar et bilde ligner henne, er det fordi det startet med henne.

## Uttrykket

Det ferdige settet sikter mot analog portrettfotografi, ikke syntetisk glamour:

- nordisk apen skygge fremfor hard studioblits
- Bergen-aktig overskyet mykhet fremfor plastkontrast
- Trondheim-stemning med praktisk lys for et forsiktig filmstillpreg
- Hardanger-varme for hud og har med litt gyllen analog tone
- Portra-inspirert farge: myk varme, beskyttede hoylys, fin kornstruktur, naturlig hud
- moden hudtekstur bevart, ikke visket bort
- ingen beauty-filter-ansiktsbytte
- ingen tvungen ungdomsutglatting

Fargegraderingen er med vilje behersket. Et godt profilbilde skal kjennes som et bedre minne av et ekte oyeblikk, ikke som om ansiktet er laminert.

## Hvordan bildene ble laget

Kildebildene ligger her:

`training/ragnhild/ai_toolkit/dataset`

De ferdige stillbildene ble laget med Ruby og `ruby-vips`. Prosessen er omtrent:

1. Velg rammene som bevarer likheten best.
2. Beskjar dem til kvadratiske profilbilde-komposisjoner.
3. Bevar ansiktsgeometrien.
4. Legg pa lett analog fargeforming.
5. Legg til fint korn og moderat skarphet.
6. Bygg ett kontaktark for vurdering.
7. Slett overflodige eksperimentfiler sa mappen holder seg ren.

Det ferdige settet har flere stemninger:

- `nordic_open_shade`: stille, rent og realistisk.
- `portra_warm`: varmere hud og mykere kontrast.
- `bergen_editorial`: klart, naturlig og lett polert.
- `trondheim_cinema`: diskre filmatisk farge og dybde.
- `hardanger_gold`: varmere gyllen analog tone.
- `mono`: svart-hvitt for identitetssjekk.

Svart-hvitt-bildene er ikke nodvendigvis hovedvalgene for glamour. De er nyttige fordi monokromt uttrykk gjor ansiktsform, oyne, uttrykk og lys lettere a vurdere uten at fargene tar over showet.

## Det som ble ryddet bort

Tidligere eksperimenter laget for mye rot:

- utforskende kontaktark
- kildegrids
- gjentatte fargevarianter
- videosnutter
- rekursive postprosesseringer
- overeksponerte `quality_uplift`-varianter

Dette er med vilje ikke en del av det ferdige profilsettet.

Oppsettet skal na unnga a lage hauger med overflodige filer. Hjelpeskriptet bruker som standard bare en ren `portrait`-postprosessering og rydder utmappen for nye genererte postpro-filer for det skriver nye.

Hjelpeskript:

`training/ragnhild/ai_toolkit/postpro_samples.rb`

## LoRA-oppsettet

LoRA-treningskonfigurasjonen er:

`training/ragnhild/ai_toolkit/train_ragnhild.yaml`

Malmodellen er fortsatt:

`black-forest-labs/FLUX.1-dev`

Det er kvalitetsvalget. Problemet er ikke den lokale Ruby-pipelinen eller promptene. Den gjeldende Hugging Face-kontoen kan logge inn, men er ikke autorisert for den lukkede FLUX-dev-modellen. Inntil den modellen kan lastes, kan vi ikke aerlig si at vi har generert et helt nytt sett Ragnhild-bilder fra den endelige FLUX LoRA-en.

Aerlig status:

- kildebaserte analoge profilbilder: ja
- rent ferdig stillbildesett: ja
- ekte nye FLUX LoRA-genereringer: ikke enda, blokkert av FLUX-dev-tilgang
- presis identitet foran alt: ja, og derfor brukes kildebaserte bilder akkurat na

## Prompt-filosofien

Valideringspromptene er skrevet for a motarbeide de vanlige AI-feilene:

- ikke gjor henne for ung
- ikke visk bort moden hudtekstur
- ikke gjor henne til en generisk influencer
- ikke bind identiteten hennes til den hvite capsen
- ikke la ett antrekk bli hele personen
- ikke la filmatisk stil overstyre ansiktsformen

Promptene beskriver henne na som en voksen norsk kvinne i 40-arene, med referanser til Bergen, Trondheim, Hardanger, nordisk dagslys, apen skygge, praktisk lys, myk analog farge og naturlige ansiktsdetaljer.

Det er ikke pynt. Det forteller modellen hva slags realisme den skal respektere.

Neste ekte LoRA-genererte sett har en strengere kreativ regel: hvert nytt bilde skal kjennes som en annen profesjonell fotografering, ikke som en liten mutasjon av forrige bilde. Ett kan vaere Bergen-regn-mot-vindu-realisme. Ett kan vaere Hardanger i gyllen time. Ett kan vaere et filmstill fra en cafe i Trondheim. Ett kan vaere svart-hvitt Tri-X-dokumentar. Ett kan vaere nordisk studioeditorial. Sted, lys, objektiv, stemning, filmstock, fargegrad, garderobe og emosjonell temperatur skal endre seg.

Det eneste som ikke skal endre seg, er Ragnhild.

Det betyr:

- radikal variasjon i fotografisk konsept
- presis kontinuitet i identitet
- voksen norsk kvinne i 40-arene, ikke generisk ung modell
- naturlig hud og uttrykk
- vakkert lys for tung stil
- analog og filmatisk polering bare etter at likheten holder

Det beste fremtidige settet skal kjennes som en liten magasinportfolio: tolv forskjellige fotoshoots, en umiskjennelig person.

## MASTER-passet

Det gjeldende `pub4/MASTER` postprosesseringsverktoyet ble testet pa profilsettet:

`../MASTER/tools/postpro.rb`

`portrait`-presetet ga brukbare resultater. `quality_uplift` ble forkastet for disse allerede graderte profilbildene fordi det overeksponerte dem. Det presetet kan fortsatt vaere nyttig senere pa ra modelloutputs, men det var ikke riktig for de ferdige kildebaserte bildene.

Den naervaerende sluttmappen beholder bare de ferdige stillbildene og ett kontaktark. De tidligere MASTER-postpro-eksperimentene var nyttige for testing, men er ikke en del av det rene ferdigsettet.

## Hvordan lese sluttsettet

Hvis Ragnhild vil ha de mest naturlige valgene, begynn med smileportrettene i de hoyere numrene. De har mest profilbilde-energi.

Hvis hun vil ha de mest identitetstro sjekkene, se pa de roligere naerportrettene og svart-hvitt-variantene. De viser om ansiktet fortsatt leses som henne uten at farge eller stemning gjor all jobben.

Hvis hun vil ha mest analog folelse, se etter `portra_warm`, `nordic_open_shade` og `hardanger_gold`.

Det beste resultatet er ikke nodvendigvis det mest dramatiske. Det beste resultatet er det der hun tenker: ja, det der er meg, bare med snillere lys.

## Neste ekte oppgradering

Neste virkelige kvalitetsloft er ikke enda et filter. Det er enten:

1. Fa Hugging Face-tilgang godkjent for `black-forest-labs/FLUX.1-dev`.
2. Kjore den tunede Ragnhild LoRA-konfigurasjonen.
3. Vurdere genererte prover for likhet for noen filmgrade legges pa.
4. Beholde bare bildene der ansiktsform, oyne, munn, alder, uttrykk og tilstedevaerelse leses som Ragnhild.
5. Deretter bruke analog og filmatisk finishing.

Rekkefolgen betyr noe. Identitet forst. Skjonnhet etterpa. Magi til slutt.

Magien far gjerne glitre litt, men den far ikke lyve.
