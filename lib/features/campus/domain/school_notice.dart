import 'package:html/dom.dart';
import 'package:html/parser.dart';

/// School notices can contain rich-text editor markup, including empty blocks.
/// Extract text only; never render or execute the supplied HTML.
String schoolNoticeText(String source) {
  final output = StringBuffer();
  void visit(Node node) {
    if (node is Text) {
      output.write(node.data.replaceAll(RegExp(r'\s+'), ' '));
    } else if (node is Element) {
      final tag = node.localName;
      if (const {'script', 'style', 'template', 'head'}.contains(tag)) return;
      final block = const {
        'p',
        'div',
        'li',
        'ul',
        'ol',
        'h1',
        'h2',
        'h3',
      }.contains(tag);
      if (block || tag == 'br') output.writeln();
      for (final child in node.nodes) {
        visit(child);
      }
      if (block) output.writeln();
    }
  }

  for (final node in parseFragment(source).nodes) {
    visit(node);
  }
  return output
      .toString()
      .replaceAll(RegExp('[\u200B\uFEFF]'), '')
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'[\s\u00A0]+'), ' ').trim())
      .where((line) => line.isNotEmpty)
      .join('\n');
}
