import '../models/models.dart';
import 'facets.dart';
import 'repo.dart';

/// The filter state of one search box: what is ticked, and whether it is remembered for
/// these search words (then it comes back next time, and recipe suggestions use it too).
class SearchFilters {
  FilterSel sel = {};
  bool remember = false;
  List<Facet> facets = [];
  String _term = '';

  /// Too many results to summarise quickly: ask for more words instead.
  static const maxSource = 6000;
  static const bestOnlyId = '_best';

  static String norm(String t) => t.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  static String keyFor(String term) => 'filters:${norm(term)}';

  /// Filters saved for a search, or null.
  static Future<FilterSel?> saved(Repo repo, String term) async {
    if (norm(term).isEmpty) return null;
    final s = await repo.setting(keyFor(term));
    return s == null || s.isEmpty ? null : Facets.decode(s);
  }

  int get count => sel.entries.fold(0, (a, e) => a + e.value.length);
  bool get bestOnly => sel[bestOnlyId]?.isNotEmpty ?? false;
  bool isOn(String facet, String key) => sel[facet]?.contains(key) ?? false;

  /// New search words: start fresh, or with what was remembered for them.
  Future<void> loadFor(Repo repo, String term) async {
    final t = norm(term);
    if (t == _term) return;
    _term = t;
    sel = {};
    remember = false;
    final s = await saved(repo, t);
    if (s != null && t == _term) {
      sel = s;
      remember = true;
    }
  }

  void toggle(String facet, String key, bool on) {
    final set = sel[facet] ??= {};
    on ? set.add(key) : set.remove(key);
    if (set.isEmpty) sel.remove(facet);
  }

  void setBestOnly(bool on) => toggle(bestOnlyId, '1', on);

  void clear() => sel = {};

  Future<void> persist(Repo repo) async {
    if (_term.isEmpty) return;
    if (remember && count > 0) {
      await repo.putSetting(keyFor(_term), Facets.encode(sel));
    } else {
      await repo.deleteSetting(keyFor(_term));
    }
  }

  /// Applies the ticks to ranked results. Filters are offered from the real matches
  /// (searching milk offers milk sizes, not chocolate bar sizes).
  ({List<Item> items, int matches}) apply(List<Item> ranked, int matches, String term) {
    final src = matches > 0 ? ranked.sublist(0, matches) : ranked;
    facets = norm(term).isEmpty || src.length > maxSource ? [] : Facets.build(src, sel, term);
    if (count == 0) return (items: ranked, matches: matches);
    final good = <Item>[], rest = <Item>[];
    for (var k = 0; k < ranked.length; k++) {
      if (!Facets.passes(ranked[k], sel)) continue;
      (k < matches ? good : rest).add(ranked[k]);
    }
    return (items: bestOnly && matches > 0 ? good : [...good, ...rest], matches: good.length);
  }
}
