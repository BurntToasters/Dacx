const int kReleaseNotesMaxEntries = 12;
const int kReleaseNotesMaxEntryLength = 220;
const int _maxBodyLength = 200000;
const int _maxRawEntryLength = 1500;

class ReleaseNotesSummary {
  const ReleaseNotesSummary({
    this.sectionVersion,
    this.entries = const [],
    this.hiddenCount = 0,
  });

  final String? sectionVersion;
  final List<String> entries;
  final int hiddenCount;

  bool get isEmpty => entries.isEmpty;
}

final RegExp _headingPattern = RegExp(r'^\s{0,3}#{1,6}(?:\s+|(?=[^#]))(.*)$');
final RegExp _changesInPattern = RegExp(
  r'^changes\s+in\b(.*)$',
  caseSensitive: false,
);
final RegExp _bulletPattern = RegExp(r'^\s*[-*+]\s+(.*)$');
final RegExp _lineBreakPattern = RegExp(r'\r\n|\r|\n');
final RegExp _imagePattern = RegExp(r'!\[[^\]]*\]\([^)]*\)');
final RegExp _linkPattern = RegExp(r'\[([^\]]*)\]\([^)]*\)');
final RegExp _htmlCommentPattern = RegExp(r'<!--.*?-->');
final RegExp _htmlTagPattern = RegExp(r'</?[A-Za-z][^>]*>');
final RegExp _boldStarPattern = RegExp(r'\*\*(.+?)\*\*');
final RegExp _boldUnderscorePattern = RegExp(r'__(.+?)__');
final RegExp _strikePattern = RegExp(r'~~(.+?)~~');
final RegExp _italicStarPattern = RegExp(
  r'(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])',
);
final RegExp _italicUnderscorePattern = RegExp(
  r'(?<!\w)_(?!\s)(.+?)(?<!\s)_(?!\w)',
);
final RegExp _codePattern = RegExp(r'`([^`]*)`');
final RegExp _whitespacePattern = RegExp(r'\s+');

ReleaseNotesSummary formatReleaseNotes(
  String? body, {
  required String version,
  int maxEntries = kReleaseNotesMaxEntries,
  int maxEntryLength = kReleaseNotesMaxEntryLength,
}) {
  try {
    if (body == null || body.trim().isEmpty) return const ReleaseNotesSummary();
    final text = body.length > _maxBodyLength
        ? body.substring(0, _maxBodyLength)
        : body;
    final sections = _collectSections(text.split(_lineBreakPattern));
    if (sections.isEmpty) return const ReleaseNotesSummary();
    final wanted = _normalizeVersion(version);
    _Section selected = sections.first;
    if (wanted.isNotEmpty) {
      for (final section in sections) {
        if (section.version == wanted) {
          selected = section;
          break;
        }
      }
    }
    return _summarize(selected, maxEntries, maxEntryLength);
  } catch (_) {
    return const ReleaseNotesSummary();
  }
}

bool isGithubReleaseUrl(String url) {
  try {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme != 'https') return false;
    if (uri.userInfo.isNotEmpty) return false;
    final host = uri.host.toLowerCase();
    return host == 'github.com' || host == 'www.github.com';
  } catch (_) {
    return false;
  }
}

class _Section {
  _Section(this.version);

  final String version;
  final List<String> lines = [];
}

String _normalizeVersion(String raw) {
  var v = raw.replaceAll(RegExp(r'[`*:\s]'), '').toLowerCase();
  if (v.startsWith('v')) v = v.substring(1);
  return v;
}

List<_Section> _collectSections(List<String> lines) {
  final sections = <_Section>[];
  _Section? current;
  for (final line in lines) {
    final heading = _headingPattern.firstMatch(line);
    if (heading != null) {
      final title = (heading.group(1) ?? '').replaceAll(RegExp(r'#+\s*$'), '');
      final changes = _changesInPattern.firstMatch(title.trim());
      if (changes != null) {
        current = _Section(_normalizeVersion(changes.group(1) ?? ''));
        sections.add(current);
      } else {
        current = null;
      }
      continue;
    }
    current?.lines.add(line);
  }
  return sections;
}

ReleaseNotesSummary _summarize(
  _Section section,
  int maxEntries,
  int maxEntryLength,
) {
  final raws = <StringBuffer>[];
  StringBuffer? open;
  for (final line in section.lines) {
    final bullet = _bulletPattern.firstMatch(line);
    if (bullet != null) {
      open = StringBuffer(bullet.group(1) ?? '');
      raws.add(open);
      continue;
    }
    if (line.trim().isEmpty) {
      open = null;
      continue;
    }
    if (open != null && (line.startsWith(' ') || line.startsWith('\t'))) {
      if (open.length < _maxRawEntryLength) open.write(' ${line.trim()}');
    } else {
      open = null;
    }
  }
  final entries = <String>[];
  var hidden = 0;
  for (final raw in raws) {
    final rawText = raw.toString();
    if (rawText.trim().isEmpty) continue;
    if (entries.length >= maxEntries) {
      hidden++;
      continue;
    }
    final cleaned = _truncate(_stripMarkup(rawText), maxEntryLength);
    if (cleaned.isEmpty) continue;
    entries.add(cleaned);
  }
  return ReleaseNotesSummary(
    sectionVersion: section.version.isEmpty ? null : section.version,
    entries: List<String>.unmodifiable(entries),
    hiddenCount: hidden,
  );
}

String _stripMarkup(String input) {
  var s = input.length > _maxRawEntryLength
      ? input.substring(0, _maxRawEntryLength)
      : input;
  s = s.replaceAll(_htmlCommentPattern, '');
  s = s.replaceAll(_imagePattern, '');
  s = s.replaceAllMapped(_linkPattern, (m) => m.group(1) ?? '');
  s = s.replaceAll(_htmlTagPattern, '');
  s = s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');
  s = s.replaceAllMapped(_boldStarPattern, (m) => m.group(1) ?? '');
  s = s.replaceAllMapped(_boldUnderscorePattern, (m) => m.group(1) ?? '');
  s = s.replaceAllMapped(_strikePattern, (m) => m.group(1) ?? '');
  s = s.replaceAllMapped(_italicStarPattern, (m) => m.group(1) ?? '');
  s = s.replaceAllMapped(_italicUnderscorePattern, (m) => m.group(1) ?? '');
  s = s.replaceAllMapped(_codePattern, (m) => m.group(1) ?? '');
  s = s.replaceAll('`', '').replaceAll('**', '');
  return s.replaceAll(_whitespacePattern, ' ').trim();
}

String _truncate(String s, int maxLength) {
  if (maxLength < 2) maxLength = 2;
  if (s.length <= maxLength) return s;
  var cut = maxLength - 1;
  final unit = s.codeUnitAt(cut - 1);
  if (unit >= 0xD800 && unit <= 0xDBFF) cut--;
  return '${s.substring(0, cut).trimRight()}…';
}
