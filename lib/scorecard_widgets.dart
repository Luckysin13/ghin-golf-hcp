import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models.dart';

class CoursePhotoViewer extends StatefulWidget {
  final String courseName;
  final String path;
  final Future<void> Function()? onDelete;

  const CoursePhotoViewer({
    super.key,
    required this.courseName,
    required this.path,
    this.onDelete,
  });

  @override
  State<CoursePhotoViewer> createState() => _CoursePhotoViewerState();
}

class _CoursePhotoViewerState extends State<CoursePhotoViewer> {
  final _zoom = ScorecardZoom();

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onDelete = widget.onDelete;
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.courseName} — scorecard'),
        actions: [
          if (onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete photo',
              onPressed: () async {
                Navigator.of(context).pop();
                await onDelete();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: scorecardImageView(
              widget.path,
              _zoom,
              key: const ValueKey('scorecard-interactive-viewer'),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ScorecardZoomControls(zoom: _zoom),
                  Text(
                    'Pinch to zoom · drag to pan',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ScorecardZoom {
  static const minScale = 1.0;
  static const maxScale = 6.0;
  static const zoomFactor = 1.5;

  final transformationController = TransformationController();
  Size viewportSize = Size.zero;

  double get scale => transformationController.value
      .getMaxScaleOnAxis()
      .clamp(minScale, maxScale)
      .toDouble();

  void zoomBy(double factor) {
    final targetScale = (scale * factor).clamp(minScale, maxScale).toDouble();
    if (targetScale == scale || viewportSize.isEmpty) return;

    final focalPoint = viewportSize.center(Offset.zero);
    final scenePoint = transformationController.toScene(focalPoint);
    transformationController.value = Matrix4.identity()
      ..translateByDouble(focalPoint.dx, focalPoint.dy, 0, 1)
      ..scaleByDouble(targetScale, targetScale, targetScale, 1)
      ..translateByDouble(-scenePoint.dx, -scenePoint.dy, 0, 1);
  }

  void reset() {
    transformationController.value = Matrix4.identity();
  }

  void dispose() => transformationController.dispose();
}

Widget scorecardImageView(String path, ScorecardZoom zoom, {Key? key}) =>
    LayoutBuilder(
      builder: (context, constraints) {
        zoom.viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        return InteractiveViewer(
          key: key,
          transformationController: zoom.transformationController,
          minScale: ScorecardZoom.minScale,
          maxScale: ScorecardZoom.maxScale,
          boundaryMargin: const EdgeInsets.all(80),
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: kIsWeb
                ? Image.network(
                    path,
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                  )
                : Image.file(
                    File(path),
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                  ),
          ),
        );
      },
    );

class ScorecardZoomControls extends StatelessWidget {
  final ScorecardZoom zoom;
  final bool compact;

  const ScorecardZoomControls({
    super.key,
    required this.zoom,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final compactStyle = compact
        ? IconButton.styleFrom(
            minimumSize: const Size(44, 44),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          )
        : null;

    return AnimatedBuilder(
      animation: zoom.transformationController,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton.filledTonal(
            tooltip: 'Zoom out',
            onPressed: zoom.scale > ScorecardZoom.minScale
                ? () => zoom.zoomBy(1 / ScorecardZoom.zoomFactor)
                : null,
            style: compactStyle,
            icon: const Icon(Icons.zoom_out),
          ),
          SizedBox(width: compact ? 2 : 8),
          SizedBox(
            width: compact ? 40 : 48,
            child: Text(
              '${(zoom.scale * 100).round()}%',
              textAlign: TextAlign.center,
              key: ValueKey(
                compact
                    ? 'course-scorecard-zoom-level'
                    : 'scorecard-zoom-level',
              ),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(width: compact ? 2 : 8),
          IconButton.filledTonal(
            tooltip: 'Zoom in',
            onPressed: zoom.scale < ScorecardZoom.maxScale
                ? () => zoom.zoomBy(ScorecardZoom.zoomFactor)
                : null,
            style: compactStyle,
            icon: const Icon(Icons.zoom_in),
          ),
          SizedBox(width: compact ? 2 : 8),
          IconButton.filledTonal(
            tooltip: 'Reset zoom and pan',
            onPressed: zoom.reset,
            style: compactStyle,
            icon: const Icon(Icons.center_focus_strong),
          ),
        ],
      ),
    );
  }
}

/// Phase 0 OCR inspector: shows the raw text Tesseract returned for the
/// last scan (copyable), so a miss can be diagnosed instead of guessed at.
void showOcrTextDialog(BuildContext context, String text) {
  showDialog(
    context: context,
    builder: (_) => OcrTextDialog(text: text),
  );
}

class OcrTextDialog extends StatelessWidget {
  final String text;
  const OcrTextDialog({super.key, required this.text});
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('What the scan read'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: SelectableText(
            text,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: text));
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('OCR text copied.')));
          },
          child: const Text('Copy'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Header colors sampled from the selected tee box, like a printed card.
///
/// The names come off the scorecard, so a course can have any of them —
/// Purple, Orange and Combo are all real. Every color a tee box can be
/// printed as is mapped here, because an unlisted name used to fall through
/// to teal and render a Purple box green.
///
/// The fallback is a neutral slate rather than a color, so a name this
/// function does not know reads as "no color known" instead of quietly
/// looking like a real tee box. Contrast on the label is picked per color:
/// dark text on the light ones, white on the dark ones.
({Color bg, Color fg}) _teeTheme(String name) {
  switch (name.trim().toLowerCase()) {
    case 'black':
      return (bg: const Color(0xFF212121), fg: Colors.white);
    case 'blue':
      return (bg: const Color(0xFF1565C0), fg: Colors.white);
    case 'white':
      return (bg: const Color(0xFFEEEEEE), fg: const Color(0xFF212121));
    case 'gold':
    case 'yellow':
      return (bg: const Color(0xFFF9A825), fg: const Color(0xFF212121));
    case 'red':
      return (bg: const Color(0xFFC62828), fg: Colors.white);
    case 'green':
      return (bg: const Color(0xFF2E7D32), fg: Colors.white);
    case 'purple':
      return (bg: const Color(0xFF6A1B9A), fg: Colors.white);
    case 'orange':
      return (bg: const Color(0xFFEF6C00), fg: const Color(0xFF212121));
    case 'bronze':
      return (bg: const Color(0xFF8D6E63), fg: Colors.white);
    case 'silver':
    case 'gray':
    case 'grey':
      return (bg: const Color(0xFF78909C), fg: Colors.white);
    default:
      return (bg: const Color(0xFF455A64), fg: Colors.white);
  }
}

/// Scorecard styled like the printed card: tee-colored header, hole
/// numbers, Par and Yds rows, OUT/IN/TOT totals. Front and back nines
/// stack vertically so every hole is reachable by scrolling.
Widget scorecardTable(Course course, Tee tee) {
  final theme = _teeTheme(tee.name);
  final front = tee.holes.take(9).toList();
  final back = tee.holes.skip(9).toList();
  int parSum(List<HoleInfo> hs) => hs.fold(0, (s, h) => s + h.par);
  int ydsSum(List<HoleInfo> hs) => hs.fold(0, (s, h) => s + h.yardage);
  String yds(int y) => y == 0 ? '—' : '$y';

  Widget nine(
    String label,
    List<HoleInfo> hs,
    String outHead, {
    String? inHead,
    int? totPar,
    int? totYds,
    required int startHole,
  }) {
    final heads = <String>[outHead];
    if (inHead != null) heads.add(inHead);
    final ratings = tee.nineHoleRatings(startHole);
    // Fixed-width centered cell with a vertical separator on its right
    // (none after the last column), so every hole column lines up.
    Widget cell(
      String s,
      Color border, {
      double width = 36,
      TextStyle? style,
      bool last = false,
    }) {
      return Container(
        width: width,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            right: last ? BorderSide.none : BorderSide(color: border),
          ),
        ),
        child: Text(s, textAlign: TextAlign.center, style: style),
      );
    }

    const headStyle = TextStyle(fontWeight: FontWeight.bold);
    const dataStyle = TextStyle(fontSize: 13);
    const boldData = TextStyle(fontSize: 13, fontWeight: FontWeight.bold);
    final headBorder = theme.fg.withValues(alpha: 0.4);
    final dataBorder = Colors.grey.withValues(alpha: 0.5);
    final lastHead = heads.length - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 2,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              if (ratings != null)
                Text(
                  'RATING ${ratings.rating.toStringAsFixed(1)}  •  SLOPE ${ratings.slope}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.25,
                    color: theme.fg.withValues(alpha: 0.72),
                  ),
                ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            horizontalMargin: 2,
            columnSpacing: 2,
            headingRowHeight: 30,
            dataRowMinHeight: 27,
            dataRowMaxHeight: 29,
            dividerThickness: 0.5,
            showCheckboxColumn: false,
            headingRowColor: WidgetStateProperty.all(theme.bg),
            headingTextStyle: TextStyle(
              color: theme.fg,
              fontWeight: FontWeight.bold,
            ),
            dataTextStyle: const TextStyle(fontSize: 13),
            columns: [
              DataColumn(
                label: cell(
                  'Hole',
                  headBorder,
                  width: 44,
                  style: headStyle.copyWith(color: theme.fg),
                ),
              ),
              for (var k = 0; k < hs.length; k++)
                DataColumn(
                  label: cell(
                    '${hs[k].number}',
                    headBorder,
                    style: headStyle.copyWith(color: theme.fg),
                  ),
                ),
              for (var k = 0; k < heads.length; k++)
                DataColumn(
                  label: cell(
                    heads[k],
                    headBorder,
                    width: 38,
                    last: k == lastHead,
                    style: headStyle.copyWith(color: theme.fg),
                  ),
                ),
            ],
            rows: [
              DataRow(
                cells: [
                  DataCell(cell('HCP', dataBorder, width: 44, style: boldData)),
                  for (var k = 0; k < hs.length; k++)
                    DataCell(
                      cell(
                        hs[k].strokeIndex?.toString() ?? '-',
                        dataBorder,
                        style: dataStyle,
                      ),
                    ),
                  for (var k = 0; k < heads.length; k++)
                    DataCell(
                      cell(
                        '—',
                        dataBorder,
                        width: 38,
                        last: k == lastHead,
                        style: dataStyle,
                      ),
                    ),
                ],
              ),
              DataRow(
                cells: [
                  DataCell(cell('Par', dataBorder, width: 44, style: boldData)),
                  for (var k = 0; k < hs.length; k++)
                    DataCell(
                      cell('${hs[k].par}', dataBorder, style: dataStyle),
                    ),
                  DataCell(
                    cell(
                      '${parSum(hs)}',
                      dataBorder,
                      width: 38,
                      last: inHead == null,
                      style: boldData,
                    ),
                  ),
                  if (inHead != null)
                    DataCell(
                      cell(
                        '$totPar',
                        dataBorder,
                        width: 38,
                        last: true,
                        style: boldData,
                      ),
                    ),
                ],
              ),
              DataRow(
                cells: [
                  DataCell(cell('Yds', dataBorder, width: 44, style: boldData)),
                  for (var k = 0; k < hs.length; k++)
                    DataCell(
                      cell(yds(hs[k].yardage), dataBorder, style: dataStyle),
                    ),
                  DataCell(
                    cell(
                      yds(ydsSum(hs)),
                      dataBorder,
                      width: 38,
                      last: inHead == null,
                      style: boldData,
                    ),
                  ),
                  if (inHead != null)
                    DataCell(
                      cell(
                        yds(totYds ?? 0),
                        dataBorder,
                        width: 38,
                        last: true,
                        style: boldData,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: theme.bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              course.name,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: theme.fg,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${tee.name} tees • Rating ${tee.rating} • Slope ${tee.slope} • Par ${tee.par} • ${tee.yardage} yd',
              style: TextStyle(
                fontSize: 12,
                color: theme.fg.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
      nine('FRONT 9', front, 'OUT', startHole: 0),
      if (back.isNotEmpty)
        nine(
          'BACK 9',
          back,
          'IN',
          inHead: 'TOT',
          totPar: parSum(tee.holes),
          totYds: ydsSum(tee.holes),
          startHole: 9,
        ),
    ],
  );
}

/// Full-screen viewer for a saved scorecard photo.
///
/// [onDelete] adds a delete button to the app bar; it runs after the viewer
/// pops itself, and is null where the photo is view-only.
void showCoursePhoto(
  BuildContext context,
  String courseName,
  String path, {
  Future<void> Function()? onDelete,
}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => CoursePhotoViewer(
        courseName: courseName,
        path: path,
        onDelete: onDelete,
      ),
    ),
  );
}
