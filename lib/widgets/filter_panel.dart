import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/facets.dart';
import '../data/search_filters.dart';
import '../theme.dart';

/// "Filters" button with the number of ticked options.
class FilterButton extends StatelessWidget {
  const FilterButton({super.key, required this.filters, required this.onPressed});
  final SearchFilters filters;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final n = filters.count;
    return Badge(
      isLabelVisible: n > 0,
      label: Text('$n'),
      backgroundColor: BB.tomato,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.tune, size: 18),
        label: const Text('Filters'),
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          backgroundColor: n > 0 ? BB.green100 : null,
        ),
      ),
    );
  }
}

/// The ticked options as chips under the search box; tap x to drop one.
class ActiveFilterChips extends StatelessWidget {
  const ActiveFilterChips({super.key, required this.filters, required this.onRemove, required this.onClear});
  final SearchFilters filters;
  final void Function(String facet, String key) onRemove;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    for (final e in filters.sel.entries) {
      for (final k in e.value) {
        final label = e.key == SearchFilters.bestOnlyId ? 'Best matches only' : Facets.labelOf(e.key, k);
        chips.add(Padding(
          padding: const EdgeInsets.only(right: 6),
          child: InputChip(
            label: Text(label, style: const TextStyle(fontSize: 12.5)),
            visualDensity: VisualDensity.compact,
            backgroundColor: BB.green100,
            onDeleted: () => onRemove(e.key, k),
          ),
        ));
      }
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          if (filters.remember)
            const Padding(
              padding: EdgeInsets.only(right: 6, top: 8),
              child: Icon(Icons.bookmark, size: 18, color: BB.goldDark),
            ),
          ...chips,
          TextButton(onPressed: onClear, child: const Text('Clear all')),
        ],
      ),
    );
  }
}

/// Side panel with every filter that makes sense for the current search, McMaster-Carr style:
/// options inside a group are alternatives, groups narrow each other, counts update live.
class FilterPanel extends StatefulWidget {
  const FilterPanel({
    super.key,
    required this.filters,
    required this.term,
    required this.resultCount,
    required this.hasOthers,
    required this.onToggle,
    required this.onClear,
    required this.onRemember,
  });
  final SearchFilters filters;
  final String term;
  final int resultCount;

  /// There are items that only contain the word; offer "best matches only".
  final bool hasOthers;
  final void Function(String facet, String key, bool on) onToggle;
  final VoidCallback onClear;
  final ValueChanged<bool> onRemember;

  @override
  State<FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<FilterPanel> {
  final Set<String> expanded = {};
  static const _shown = 8;

  @override
  Widget build(BuildContext context) {
    final f = widget.filters;
    final term = widget.term.trim();
    final width = math.min(MediaQuery.sizeOf(context).width * 0.88, 380.0);
    return Drawer(
      width: width,
      backgroundColor: BB.cream,
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(children: [
              Expanded(child: Text('Filters', style: serif(24))),
              if (f.count > 0) TextButton(onPressed: widget.onClear, child: const Text('Clear all')),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              children: [
                if (term.isNotEmpty)
                  SwitchListTile(
                    dense: true,
                    value: f.remember,
                    onChanged: widget.onRemember,
                    title: Text('Remember for "$term"', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Ticks come back every time you search this, and recipes pick to match.'),
                  ),
                if (widget.hasOthers || f.bestOnly)
                  SwitchListTile(
                    dense: true,
                    value: f.bestOnly,
                    onChanged: (v) => widget.onToggle(SearchFilters.bestOnlyId, '1', v),
                    title: const Text('Best matches only', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('Hide items that only contain the word${term.isEmpty ? '' : ' "$term"'}.'),
                  ),
                if (f.facets.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                        term.isEmpty
                            ? 'Search for something first; the filters that fit it show up here.'
                            : 'No filters for these results. Try one or two more words.',
                        style: const TextStyle(color: BB.muted)),
                  ),
                for (final facet in f.facets) ..._section(facet),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Show ${widget.resultCount} items'),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  List<Widget> _section(Facet facet) {
    final f = widget.filters;
    final open = expanded.contains(facet.id);
    // Keep ticked options visible even when the list is folded.
    final visible = open
        ? facet.options
        : [
            for (var k = 0; k < facet.options.length; k++)
              if (k < _shown || f.isOn(facet.id, facet.options[k].key)) facet.options[k],
          ];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 2),
        child: Text(facet.title, style: serif(17)),
      ),
      for (final o in visible)
        CheckboxListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          value: f.isOn(facet.id, o.key),
          onChanged: (v) => widget.onToggle(facet.id, o.key, v ?? false),
          title: Row(children: [
            Expanded(
              child: Text(o.label,
                  style: TextStyle(color: o.count == 0 ? BB.muted : BB.ink, fontSize: 14)),
            ),
            Text('${o.count}', style: const TextStyle(color: BB.muted, fontSize: 12.5)),
          ]),
        ),
      if (facet.options.length > _shown)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => open ? expanded.remove(facet.id) : expanded.add(facet.id)),
            child: Text(open ? 'Show fewer' : 'Show all ${facet.options.length}'),
          ),
        ),
    ];
  }
}
