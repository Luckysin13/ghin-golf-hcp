# GHIN Golf 

Local-first golf handicap app: 

Course search checks the local course catalog.
Choose **Import** to load every tee row
for that facility. Course rating, slope, total par, and available front/back-nine
ratings and slopes come from the local catalog.

## Test on PC (no toolchain needed)

```bash
cd ~/ghin-golf
flutter test            # WHS vectors + widget boot test
flutter build web --release
cd build/web && python3 -m http.server 8080
# open http://localhost:8080 in Brave/any browser
```

`flutter run -d linux` additionally requires:
`clang cmake ninja-build libgtk-3-dev mesa-utils` (needs sudo).

## Code layout

`lib/main.dart` holds boot, tabs, and Home. The other screens live in
`lib/post_page.dart` (Play), `lib/courses_page.dart` (Courses),
`lib/add_course_screen.dart`, and `lib/stats_page.dart`, with shared pieces
in `lib/score_widgets.dart`, `lib/scorecard_widgets.dart`, and
`lib/text_format.dart`. Saves persist to `ghin-golf.json` in the platform
app-support directory; pre-removal `ncrdb-*` ids migrate on load.
