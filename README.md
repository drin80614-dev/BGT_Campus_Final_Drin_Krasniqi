# BGT Campus — Projekti final Day 5

Autori: Drin Krasniqi
Teknologjitë: Flutter, Dart dhe Supabase.

## Plani
Aplikacioni shërben për organizimin e eventeve të shkollës,
komunikimin në chat dhe votimin për aktivitetet.

Ka katër tab-a: Home, Eventet, Chat dhe Profili.

## Funksionet
- Login dhe regjistrim me Supabase Auth.
- Leximi i eventeve dhe faqja e detajeve.
- Shtimi me formë dhe validim.
- Ndryshimi dhe fshirja vetëm nga pronari.
- RLS kontrollon pronarin edhe në databazë.
- Lista rifreskohet automatikisht çdo 3 sekonda.
- Kërkimi dhe filtrat “Të gjitha” / “Të miat”.
- Tema e ndritshme dhe dark mode.
- Profili dhe dalja.
- SnackBar për sukseset dhe gabimet.
- Chat me mesazhet personale djathtas.
- Votim me një votë për përdorues.

## Konfigurimi
1. Ekzekutoni Day5_SQL.txt në Supabase → SQL Editor.
2. Vendosni main.dart te lib/main.dart në FlutLab.
3. Te pubspec.yaml duhet varësia http: ^1.2.2.
4. Kryeni Pub Get dhe Build.
5. Regjistrohuni ose kyçuni në aplikacion.

Nëse konfirmimi i email-it është aktiv, konfirmoni email-in.
Për ndryshim/fshirje krijoni event të ri nga përdoruesi i kyçur.
Eventet e vjetra pa user_id nuk kanë pronar në app.

## Gjendjet e listës
Ngarkim, gabim me “Provo përsëri”, listë bosh dhe listë me të dhëna.

## Lista live
Përdoret polling me REST çdo 3 sekonda dhe StreamBuilder.
Sesioni dhe tema ruhen në memorie gjatë përdorimit të app-it.

## Skedarët
- main.dart
- Day5_SQL.txt
- README.md

## GitHub
https://github.com/drin80614-dev/BGT_Campus_Final_Drin_Krasniqi

## Dorëzimi
Të tre skedarët paketohen në BGT_Campus_Final.zip.
Nuk kërkohen screenshots.