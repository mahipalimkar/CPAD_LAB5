import 'dart:async';
import 'dart:convert';
import 'dart:html';

/// Formatting state for ONE text element. The DOM is always drawn from this.
class Fmt {
  String text;
  final String defaultText;
  int? size; // px, null = stylesheet default
  int spacing = 0; // letter-spacing in px
  String family = '';
  String? color; // hex, null = stylesheet default
  String align = ''; // left | center | right | '' (default)
  final Set<String> classes = {};

  Fmt(String t) : text = t, defaultText = t;

  void resetStyle() {
    size = null;
    spacing = 0;
    family = '';
    color = null;
    align = '';
    classes.clear();
  }

  void apply(Map<String, Object> m) {
    color = m['color'] as String?;
    family = m['family'] as String? ?? '';
    size = m['size'] as int?;
    spacing = m['spacing'] as int? ?? 0;
    align = m['align'] as String? ?? '';
    classes
      ..clear()
      ..addAll((m['classes'] as List?)?.cast<String>() ?? const <String>[]);
  }

  Map<String, Object?> toJson() => {
    'text': text,
    'size': size,
    'spacing': spacing,
    'family': family,
    'color': color,
    'align': align,
    'classes': classes.toList(),
  };

  void loadJson(Map m) {
    text = m['text'] as String? ?? text;
    size = m['size'] as int?;
    spacing = m['spacing'] as int? ?? 0;
    family = m['family'] as String? ?? '';
    color = m['color'] as String?;
    align = m['align'] as String? ?? '';
    classes
      ..clear()
      ..addAll(((m['classes'] as List?) ?? []).cast<String>());
  }
}

const alignSelf = {
  'left': 'flex-start',
  'center': 'center',
  'right': 'flex-end',
};
const allClasses = ['fmt-italic', 'fmt-underline', 'fmt-upper', 'hl'];
const defaultSize = {'title': 37, 'message': 16};

const presets = <String, Map<String, Map<String, Object>>>{
  'ocean': {
    'title': {
      'color': '#0369a1',
      'family': 'Georgia, serif',
      'size': 44,
      'spacing': 1,
    },
    'message': {
      'color': '#0e7490',
      'family': 'Georgia, serif',
      'classes': ['fmt-italic'],
    },
  },
  'sunset': {
    'title': {
      'color': '#ea580c',
      'size': 46,
      'spacing': 2,
      'classes': ['fmt-upper'],
    },
    'message': {'color': '#be123c', 'size': 18},
  },
  'forest': {
    'title': {'color': '#15803d', 'family': 'Georgia, serif', 'size': 42},
    'message': {'color': '#166534', 'family': 'Georgia, serif'},
  },
  'terminal': {
    'title': {
      'color': '#22c55e',
      'family': 'Consolas, monospace',
      'size': 36,
      'spacing': 2,
    },
    'message': {
      'color': '#22c55e',
      'family': 'Consolas, monospace',
      'classes': ['hl'],
    },
  },
};

void main() {
  final title = querySelector('#title')!;
  final message = querySelector('#message')!;
  final studioBtn = querySelector('#studioBtn')!;
  final themeBtn = querySelector('#themeBtn')!;
  final exportBtn = querySelector('#exportBtn')!;
  final addBtn = querySelector('#addBtn')!;
  final clearBtn = querySelector('#clearBtn')!;
  final input = querySelector('#taskInput') as InputElement;
  final search = querySelector('#searchInput') as InputElement;
  final dueInput = querySelector('#dueInput') as InputElement;
  final accentPick = querySelector('#accentPick') as InputElement;
  final prioritySel = querySelector('#prioritySel') as SelectElement;
  final list = querySelector('#list')!;
  final empty = querySelector('#empty')!;
  final status = querySelector('#status')!;
  final clock = querySelector('#clock')!;
  final bar = querySelector('#bar')!;
  final toasts = querySelector('#toasts')!;
  final totalCount = querySelector('#totalCount')!;
  final doneCount = querySelector('#doneCount')!;
  final pendingCount = querySelector('#pendingCount')!;
  final tabs = querySelectorAll('.tab');

  // Style Studio elements
  final studio = querySelector('#studio')!;
  final textInput = querySelector('#textInput') as InputElement;
  final sizeRange = querySelector('#sizeRange') as InputElement;
  final spacingRange = querySelector('#spacingRange') as InputElement;
  final familySel = querySelector('#familySel') as SelectElement;
  final textColor = querySelector('#textColor') as InputElement;
  final sizeVal = querySelector('#sizeVal')!;
  final spacingVal = querySelector('#spacingVal')!;
  final resetBtn = querySelector('#resetBtn')!;
  final cssOut = querySelector('#cssOut')!;
  final targetChips = querySelectorAll('#targetSeg .chip');
  final alignChips = querySelectorAll('#alignSeg .chip');
  final togChips = querySelectorAll('#togSeg .chip');
  final presetChips = querySelectorAll('#presetSeg .chip');

  String filter = 'all';
  Element? dragged;
  const names = {'low': 'Low', 'med': 'Medium', 'high': 'High'};

  void setStatus(String t) => status.text = 'Status: $t';

  // ---------- Toast ----------
  void toast(String msg, {void Function()? undo}) {
    final t = DivElement()
      ..classes.add('toast')
      ..text = msg;
    if (undo != null) {
      final b = ButtonElement()..text = 'Undo';
      b.onClick.listen((_) {
        undo();
        t.remove();
      });
      t.append(b);
    }
    toasts.append(t);
    Timer(const Duration(seconds: 4), () => t.remove());
  }

  // ---------- Style Studio: state -> DOM ----------
  final targets = {'title': title, 'message': message};
  final fmts = {
    'title': Fmt(title.text ?? ''),
    'message': Fmt(message.text ?? ''),
  };
  String current = 'title';
  String who() => current == 'title' ? 'heading' : 'paragraph';

  // Set a CSS property, or remove it when there is no value
  void put(Element el, String prop, String? v) {
    if (v == null || v.isEmpty) {
      el.style.removeProperty(prop);
    } else {
      el.style.setProperty(prop, v);
    }
  }

  void saveFmt() {
    window.localStorage['fmt'] = jsonEncode({
      for (final k in fmts.keys) k: fmts[k]!.toJson(),
    });
  }

  void updateReadout() {
    final el = targets[current]!;
    cssOut.text =
        '<${el.tagName.toLowerCase()} id="${el.id}">\n'
        'style="${el.getAttribute('style') ?? ''}"\n'
        'class="${el.className}"';
  }

  void render(String key) {
    final el = targets[key]!;
    final f = fmts[key]!;
    el.text = f.text;
    put(el, 'font-size', f.size == null ? null : '${f.size}px');
    put(el, 'letter-spacing', f.spacing == 0 ? null : '${f.spacing}px');
    put(el, 'font-family', f.family);
    put(el, 'color', f.color);
    put(el, 'text-align', f.align);
    put(el, 'align-self', alignSelf[f.align]);
    for (final c in allClasses) {
      el.classes.toggle(c, f.classes.contains(c));
    }
    if ((el.getAttribute('style') ?? '').isEmpty) el.removeAttribute('style');
    saveFmt();
    updateReadout();
  }

  void syncChips() {
    final f = fmts[current]!;
    for (final c in alignChips) {
      c.classes.toggle('active', c.dataset['align'] == f.align);
    }
    for (final c in togChips) {
      c.classes.toggle('active', f.classes.contains(c.dataset['class']));
    }
  }

  // Make the controls show the values of the selected target
  void syncControls() {
    final f = fmts[current]!;
    textInput.value = f.text;
    sizeRange.value = '${f.size ?? defaultSize[current]!}';
    sizeVal.text = f.size == null ? 'default' : '${f.size}px';
    spacingRange.value = '${f.spacing}';
    spacingVal.text = '${f.spacing}px';
    familySel.value = f.family;
    textColor.value = f.color ?? '#6366f1';
    syncChips();
    updateReadout();
  }

  // Every control goes through here: change state -> render -> report
  void update(void Function(Fmt f) change, String note) {
    change(fmts[current]!);
    render(current);
    syncChips();
    setStatus(note);
  }

  studioBtn.onClick.listen((_) {
    studio.hidden = !studio.hidden;
    setStatus(studio.hidden ? 'Style Studio hidden.' : 'Style Studio opened.');
  });

  for (final c in targetChips) {
    c.onClick.listen((_) {
      current = c.dataset['target']!;
      for (final o in targetChips) {
        o.classes.toggle('active', o == c);
      }
      syncControls();
      setStatus('now editing the ${who()} (#$current).');
    });
  }

  textInput.onInput.listen((_) {
    final v = textInput.value ?? '';
    update(
      (f) => f.text = v,
      '${who()} text updated through the text property.',
    );
  });

  sizeRange.onInput.listen((_) {
    final v = int.parse(sizeRange.value!);
    sizeVal.text = '${v}px';
    update(
      (f) => f.size = v,
      '${who()} font-size set to ${v}px (inline style).',
    );
  });

  spacingRange.onInput.listen((_) {
    final v = int.parse(spacingRange.value!);
    spacingVal.text = '${v}px';
    update(
      (f) => f.spacing = v,
      '${who()} letter-spacing set to ${v}px (inline style).',
    );
  });

  familySel.onChange.listen((_) {
    final v = familySel.value ?? '';
    update((f) => f.family = v, '${who()} font-family changed (inline style).');
  });

  textColor.onInput.listen((_) {
    final v = textColor.value!;
    update((f) => f.color = v, '${who()} colour set to $v (inline style).');
  });

  for (final c in alignChips) {
    c.onClick.listen((_) {
      final a = c.dataset['align']!;
      update(
        (f) => f.align = f.align == a ? '' : a,
        '${who()} alignment toggled: $a.',
      );
    });
  }

  for (final c in togChips) {
    c.onClick.listen((_) {
      final k = c.dataset['class']!;
      update((f) {
        if (!f.classes.remove(k)) f.classes.add(k);
      }, 'class "$k" toggled on the ${who()}.');
    });
  }

  for (final c in presetChips) {
    c.onClick.listen((_) {
      final name = c.dataset['preset']!;
      for (final key in targets.keys) {
        final f = fmts[key]!;
        f.resetStyle();
        final p = presets[name];
        if (p != null) f.apply(p[key]!);
        render(key);
      }
      syncControls();
      setStatus('preset "$name" applied to the heading and paragraph.');
    });
  }

  resetBtn.onClick.listen((_) {
    final f = fmts[current]!;
    f.resetStyle();
    f.text = f.defaultText;
    render(current);
    syncControls();
    setStatus('${who()} reset: inline styles and classes removed.');
  });

  // Restore saved formatting
  final savedFmt = window.localStorage['fmt'];
  if (savedFmt != null) {
    final m = jsonDecode(savedFmt) as Map;
    for (final k in targets.keys) {
      if (m[k] != null) {
        fmts[k]!.loadJson(m[k] as Map);
        render(k);
      }
    }
  }
  syncControls();

  // ---------- Stats, filter, save ----------
  void setStat(Element el, int v) {
    if (el.text == '$v') return;
    el.text = '$v';
    el.classes.add('bump');
    Future.delayed(
      const Duration(milliseconds: 200),
      () => el.classes.remove('bump'),
    );
  }

  void save() {
    final data = list.children
        .map(
          (li) => {
            'text': li.querySelector('.label')!.text,
            'pri': li.dataset['pri'],
            'due': li.dataset['due'] ?? '',
            'done': li.classes.contains('done'),
          },
        )
        .toList();
    window.localStorage['tasks'] = jsonEncode(data);
  }

  void applyFilter() {
    final q = (search.value ?? '').toLowerCase();
    for (final li in list.children) {
      final done = li.classes.contains('done');
      final tabOk = filter == 'all' || (filter == 'done' ? done : !done);
      final textOk = li
          .querySelector('.label')!
          .text!
          .toLowerCase()
          .contains(q);
      li.hidden = !(tabOk && textOk);
    }
  }

  void updateStats() {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    for (final li in list.children) {
      final due = li.dataset['due'] ?? '';
      final done = li.classes.contains('done');
      li.classes.toggle(
        'overdue',
        !done && due.isNotEmpty && due.compareTo(today) < 0,
      );
    }
    final total = list.children.length;
    final done = list.querySelectorAll('li.done').length;
    setStat(totalCount, total);
    setStat(doneCount, done);
    setStat(pendingCount, total - done);
    bar.style.width = total == 0 ? '0%' : '${(done * 100 / total).round()}%';
    empty.hidden = total > 0;
    applyFilter();
    save();
  }

  // ---------- Clock, theme, accent, export ----------
  String two(int n) => n.toString().padLeft(2, '0');
  void tick() {
    final n = DateTime.now();
    clock.text = '${two(n.hour)}:${two(n.minute)}:${two(n.second)}';
  }

  tick();
  Timer.periodic(const Duration(seconds: 1), (_) => tick());

  themeBtn.onClick.listen((_) {
    final dark = document.body!.classes.toggle('dark');
    setStatus(
      dark
          ? 'dark mode ON (class added to body).'
          : 'dark mode OFF (class removed).',
    );
  });

  void applyAccent(String c) => document.body!.style.setProperty('--accent', c);
  accentPick.onInput.listen((_) {
    applyAccent(accentPick.value!);
    window.localStorage['accent'] = accentPick.value!;
    setStatus('CSS variable --accent set to ${accentPick.value}.');
  });

  exportBtn.onClick.listen((_) {
    final data = list.children
        .map(
          (li) => {
            'text': li.querySelector('.label')!.text,
            'priority': li.dataset['pri'],
            'due': li.dataset['due'] ?? '',
            'done': li.classes.contains('done'),
          },
        )
        .toList();
    final blob = Blob([
      const JsonEncoder.withIndent('  ').convert(data),
    ], 'application/json');
    final url = Url.createObjectUrlFromBlob(blob);
    AnchorElement(href: url)
      ..download = 'tasks.json'
      ..click();
    Url.revokeObjectUrl(url);
    toast('Exported ${data.length} task(s) to tasks.json');
    setStatus('tasks exported through a Blob download link.');
  });

  // ---------- Tasks ----------
  void createTask(String text, String pri, bool isDone, String due, {int? at}) {
    final item = LIElement()
      ..dataset['pri'] = pri
      ..dataset['due'] = due
      ..draggable = true;
    if (isDone) item.classes.add('done');

    final check = ButtonElement()..classes.add('check');
    final label = SpanElement()
      ..classes.add('label')
      ..text = text;
    final tag = SpanElement()
      ..classes.add('tag')
      ..text = names[pri];
    final dueTag = SpanElement()
      ..classes.add('due')
      ..text = due.isEmpty ? '' : 'Due $due';
    final del = ButtonElement()
      ..classes.add('del')
      ..text = 'Remove';

    check.onClick.listen((_) {
      final d = item.classes.toggle('done');
      updateStats();
      setStatus(
        d
            ? 'task "${label.text}" marked complete.'
            : 'task "${label.text}" marked pending.',
      );
    });

    var before = text;
    label.onDoubleClick.listen((_) {
      before = label.text ?? '';
      item.draggable = false;
      label.contentEditable = 'true';
      label.focus();
      setStatus('editing "$before" (Enter to save).');
    });
    label.onKeyDown.listen((e) {
      if (e.key == 'Enter') {
        e.preventDefault();
        label.blur();
      }
    });
    label.onBlur.listen((_) {
      if (label.contentEditable != 'true') return;
      label.contentEditable = 'false';
      item.draggable = true;
      final v = (label.text ?? '').trim();
      label.text = v.isEmpty ? before : v;
      updateStats();
      setStatus('task text updated to "${label.text}".');
    });

    del.onClick.listen((_) {
      final index = list.children.indexOf(item);
      final t = label.text ?? '';
      final d = item.classes.contains('done');
      item.classes.add('removing');
      Future.delayed(const Duration(milliseconds: 250), () {
        item.remove();
        updateStats();
        setStatus('item "$t" removed from the DOM.');
        toast(
          'Removed "$t"',
          undo: () {
            createTask(t, pri, d, due, at: index);
            updateStats();
            setStatus('removal undone: "$t" restored.');
          },
        );
      });
    });

    item.onDragStart.listen((e) {
      dragged = item;
      item.classes.add('dragging');
      e.dataTransfer.effectAllowed = 'move';
      e.dataTransfer.setData('text/plain', '');
    });
    item.onDragOver.listen((e) {
      e.preventDefault();
      final d = dragged;
      if (d == null || d == item) return;
      final r = item.getBoundingClientRect();
      final after = e.client.y > r.top + r.height / 2;
      list.insertBefore(d, after ? item.nextElementSibling : item);
    });
    item.onDragEnd.listen((_) {
      item.classes.remove('dragging');
      dragged = null;
      save();
      setStatus('task order changed by drag and drop.');
    });

    item
      ..append(check)
      ..append(label)
      ..append(dueTag)
      ..append(tag)
      ..append(del);

    if (at != null && at < list.children.length) {
      list.insertBefore(item, list.children[at]);
    } else {
      list.append(item);
    }
  }

  void addTask() {
    final text = input.value?.trim() ?? '';
    if (text.isEmpty) {
      input.classes.remove('error');
      Future.microtask(() => input.classes.add('error'));
      setStatus('please type something before adding.');
      return;
    }
    input.classes.remove('error');
    final pri = prioritySel.value ?? 'med';
    createTask(text, pri, false, dueInput.value ?? '');
    input.value = '';
    dueInput.value = '';
    input.focus();
    updateStats();
    setStatus('new <li> created: "$text" (${names[pri]} priority).');
  }

  addBtn.onClick.listen((_) => addTask());
  input.onKeyDown.listen((e) {
    if (e.key == 'Enter') addTask();
  });
  input.onInput.listen((_) => input.classes.remove('error'));

  search.onInput.listen((_) {
    applyFilter();
    setStatus('filtering tasks by "${search.value}".');
  });
  for (final tab in tabs) {
    tab.onClick.listen((_) {
      filter = tab.dataset['filter']!;
      for (final t in tabs) {
        t.classes.toggle('active', t == tab);
      }
      applyFilter();
      setStatus('showing "$filter" tasks.');
    });
  }

  clearBtn.onClick.listen((_) {
    final done = list.querySelectorAll('li.done');
    for (final li in done) {
      li.remove();
    }
    updateStats();
    toast('${done.length} completed task(s) cleared');
    setStatus('${done.length} completed task(s) removed.');
  });

  document.onKeyDown.listen((e) {
    final tag = document.activeElement?.tagName;
    if (e.key == '/' && tag != 'INPUT' && tag != 'SPAN' && tag != 'SELECT') {
      e.preventDefault();
      search.focus();
    }
  });

  // ---------- Restore ----------
  final savedAccent = window.localStorage['accent'];
  if (savedAccent != null) {
    accentPick.value = savedAccent;
    applyAccent(savedAccent);
  }
  final saved = window.localStorage['tasks'];
  if (saved != null) {
    for (final t in jsonDecode(saved)) {
      createTask(
        t['text'],
        t['pri'] ?? 'med',
        t['done'] == true,
        t['due'] ?? '',
      );
    }
  }
  updateStats();
}
