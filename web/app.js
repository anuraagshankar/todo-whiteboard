const canvas = document.getElementById('canvas');
const themeBtn = document.getElementById('theme');
const addBtn = document.getElementById('add');

const ICONS = {
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
  moon: '<path d="M20 14.5A8 8 0 0 1 9.5 4 8 8 0 1 0 20 14.5z"/>',
  checklist: '<rect x="3" y="4" width="6" height="6" rx="1"/><path d="M4.5 7l1.2 1.2L8 5.8M3 15h6v6H3zM13 7h8M13 18h8"/>',
  text: '<path d="M4 6h16M4 12h16M4 18h10"/>',
  trash: '<path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/>',
  tick: '<path d="M6 12.5l4 4 8-9"/>',
  close: '<path d="M6 6l12 12M18 6L6 18"/>',
  back: '<path d="M15 5l-7 7 7 7"/>',
  grip: '<circle cx="8.5" cy="5" r="2"/><circle cx="15.5" cy="5" r="2"/><circle cx="8.5" cy="12" r="2"/><circle cx="15.5" cy="12" r="2"/><circle cx="8.5" cy="19" r="2"/><circle cx="15.5" cy="19" r="2"/>',
  broom:
    '<path d="M18 2l-3.4 7.5M11.4 11.4c.3-1.6 1.7-2.4 3.1-2s2.1 1.9 1.5 3.4zM13.4 13c-1 2.1-1.8 4.6-1.9 7.2"/>' +
    '<path d="M11.4 11.4C9.2 13.6 7.4 16.6 6.4 20.2q1.4-1.2 2.6.4 1.1-1.6 2.5.3 1.1-1.6 2.5 0 1.1-1.4 2.6-.6C16.9 17.2 16.6 15 16 12.8"/>',
};
const svg = (name) => `<svg viewBox="0 0 24 24">${ICONS[name]}</svg>`;

// Theme: starts from the system setting, then the toggle flips it.
// The icon shows the mode a click switches to.
const root = document.documentElement;
function setTheme(theme) {
  root.dataset.theme = theme;
  themeBtn.innerHTML = svg(theme === 'dark' ? 'sun' : 'moon');
}
setTheme(matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
themeBtn.addEventListener('click', () => setTheme(root.dataset.theme === 'dark' ? 'light' : 'dark'));

// Notes, shared by the Mac and iPhone views. Each note is
// { id, title, mode, text, items, x, y, w, h, z }: x/y are null until it is first
// placed on the Mac canvas, h is null while it grows with its content.
// note.el (and modeBtn/clearBtn) point at whichever editor is showing it.
const NOTE_W = 288; // includes the column reserved for item delete buttons
const NOTE_H = 160; // starting (minimum) height; notes grow with content up to 75% of the page height
const GAP = 16; // minimum space kept between a new note and existing ones
const STEP = 24; // grid the empty-space search walks, matches the dot grid
const notes = [];

const newNote = () => ({ id: crypto.randomUUID(), title: '', mode: 'text', text: '', items: [], x: null, y: null, w: NOTE_W, h: null, z: 0 });

// Mode button shows the note's current mode.
const MODES = {
  text: { icon: 'text', label: 'Plain text mode (click for checkboxes)', next: 'checklist' },
  checklist: { icon: 'checklist', label: 'Checkbox mode (click for plain text)', next: 'text' },
};

const EDITOR_HTML = `
  <input class="title" placeholder="Title" aria-label="Title">
  <hr>
  <div class="body"></div>
  <hr>
  <footer>
    <div class="left">
      <button class="mode"></button>
      <button class="clear-done" title="Delete marked items" aria-label="Delete marked items">${svg('broom')}</button>
    </div>
    <button class="trash" title="Delete note" aria-label="Delete note">${svg('trash')}</button>
  </footer>`;

// Wires the editor markup inside el to note.
function mountEditor(note, el) {
  note.el = el;
  note.modeBtn = el.querySelector('.mode');
  note.clearBtn = el.querySelector('.clear-done');
  const title = el.querySelector('.title');
  title.value = note.title;
  title.addEventListener('input', () => {
    note.title = title.value;
    save(note);
  });
  note.modeBtn.addEventListener('click', () => setMode(note, MODES[note.mode].next));
  note.clearBtn.addEventListener('click', () => clearDone(note));
  el.querySelector('.trash').addEventListener('click', () => deleteNote(note));
  showMode(note);
}

function setMode(note, mode) {
  if (note.mode === 'checklist' && mode === 'text') note.text = itemsToText(note.items);
  if (note.mode === 'text' && mode === 'checklist') note.items = textToItems(note.text);
  note.mode = mode;
  showMode(note);
  save(note);
}

function showMode(note) {
  note.modeBtn.innerHTML = svg(MODES[note.mode].icon);
  note.modeBtn.title = MODES[note.mode].label;
  note.clearBtn.hidden = note.mode !== 'checklist';
  renderBody(note);
}

// Body. Plain text mode is one textarea (note.text). Checkbox mode is a flat list (note.items) of
// { text, done, level } items, level 0 or 1; a level-1 item belongs to the
// nearest level-0 item above it. Unmarked items show first, marked ones in a
// Done section below; a sub-item is shown nested only when its parent is in
// the same section.
const parentOf = (items, i) => {
  for (let j = i - 1; j >= 0; j--) if (items[j].level === 0) return j;
  return -1;
};
const isNested = (items, i) => {
  const p = parentOf(items, i);
  return items[i].level === 1 && p !== -1 && items[p].done === items[i].done;
};

// Mode switching converts the content. Checkbox -> text, in on-screen order:
//   - item
//   \t- sub-item
//   # Done:
//   # marked item
//   \t# marked sub-item
// Text -> checkbox reads the same format back: one item per non-empty line,
// a leading tab nests it, a leading "- " (or "# " after "# Done:") is stripped.
const DONE_HEADER = '# Done:';

function itemsToText(items) {
  const lines = (done, mark) =>
    items
      .map((it, i) => (it.done === done && it.text.trim() ? `${isNested(items, i) ? '\t' : ''}${mark} ${it.text}` : null))
      .filter((line) => line !== null);
  const active = lines(false, '-');
  const done = lines(true, '#');
  return [...active, ...(done.length ? [DONE_HEADER, ...done] : [])].join('\n');
}

function textToItems(text) {
  const items = [];
  let done = false;
  let hasParent = false; // a top-level item exists above, in the current section
  for (const line of text.split(/\r?\n/)) {
    if (line.trim() === DONE_HEADER) {
      done = true;
      hasParent = false;
      continue;
    }
    const nested = line.startsWith('\t') && hasParent;
    const content = line.trimStart().replace(done ? /^# / : /^- /, '');
    if (!content.trim()) continue;
    items.push({ text: content, done, level: nested ? 1 : 0 });
    if (!nested) hasParent = true;
  }
  return items;
}

function renderBody(note, focus) {
  const body = note.el.querySelector('.body');
  body.replaceChildren();

  if (note.mode === 'text') {
    const area = document.createElement('textarea');
    area.value = note.text;
    area.addEventListener('input', () => {
      note.text = area.value;
      fit(area);
      save(note);
    });
    // Tab types a tab character instead of moving focus to the next button.
    // insertText goes through the browser's editing, so Cmd+Z undoes it like
    // typed text (setting the value directly breaks the undo history).
    area.addEventListener('keydown', (e) => {
      if (e.key !== 'Tab' || e.shiftKey || e.altKey || e.metaKey || e.ctrlKey) return;
      e.preventDefault();
      if (!document.execCommand('insertText', false, '\t')) {
        area.setRangeText('\t', area.selectionStart, area.selectionEnd, 'end');
        area.dispatchEvent(new Event('input'));
      }
    });
    body.append(area);
    fit(area);
    return;
  }

  // Items are one-line textareas that wrap and grow (Enter never adds a newline).
  const { items } = note;
  if (!items.some((it) => !it.done)) items.push({ text: '', done: false, level: 0 });
  const section = (done) => {
    const list = document.createElement('div');
    items.forEach((it, i) => {
      if (it.done === done) list.append(itemRow(note, i, isNested(items, i)));
    });
    return list;
  };
  body.append(section(false));
  if (items.some((it) => it.done)) body.append(document.createElement('hr'), section(true));
  body.querySelectorAll('textarea').forEach(fit);

  if (focus) {
    const input = body.querySelector(`.text[data-i="${focus.i}"]`);
    const caret = focus.caret ?? input.value.length;
    input.focus();
    input.setSelectionRange(caret, caret);
  }
}

// Size the textarea to its content so the note grows instead of scrolling.
function fit(area) {
  const body = area.closest('.body');
  const scroll = body.scrollTop; // resetting the height would jump the scroll once the note is at max height
  area.style.height = 'auto';
  area.style.height = `${area.scrollHeight}px`;
  body.scrollTop = scroll;
}

function itemRow(note, i, nested) {
  const it = note.items[i];
  const row = document.createElement('div');
  row.className = `item${nested ? ' sub' : ''}${it.done ? ' done' : ''}`;
  row.dataset.i = i;
  // Grip, shown on hover in the margin left of the box: drag to reorder.
  const grip = document.createElement('button');
  grip.className = 'grip';
  grip.title = 'Drag to reorder';
  grip.setAttribute('aria-label', 'Drag to reorder');
  grip.innerHTML = svg('grip');
  grip.addEventListener('pointerdown', (e) => dragItem(note, i, row, e));
  // Outlined box, with a tick when marked (not a filled native checkbox).
  const box = document.createElement('button');
  box.className = 'box';
  box.setAttribute('role', 'checkbox');
  box.setAttribute('aria-checked', it.done);
  if (it.done) box.innerHTML = svg('tick');
  box.addEventListener('click', () => toggleItem(note, i));
  const text = document.createElement('textarea');
  text.className = 'text';
  text.rows = 1;
  text.value = it.text;
  text.dataset.i = i;
  text.readOnly = it.done;
  text.addEventListener('input', () => {
    if (text.value.includes('\n')) {
      // Pasted line breaks become spaces: an item is a single (wrapping) line.
      const caret = text.selectionStart;
      text.value = text.value.replace(/\n/g, ' ');
      text.setSelectionRange(caret, caret);
    }
    it.text = text.value;
    fit(text);
    save(note);
  });
  text.addEventListener('keydown', (e) => itemKey(note, i, text, e));
  // Delete button, shown on hover, in its own column the text never flows into.
  const remove = document.createElement('button');
  remove.className = 'remove';
  remove.title = 'Delete item';
  remove.setAttribute('aria-label', 'Delete item');
  remove.innerHTML = svg('close');
  remove.addEventListener('click', () => {
    removeItem(note, i);
    renderBody(note);
    save(note);
  });
  row.append(grip, box, text, remove);
  return row;
}

// Drag an item by its grip to reorder it within its section; a parent carries
// its sub-items. Dragging right of where it started makes it a sub-item, left
// makes it top-level, where allowed: a drop inside a group is always a
// sub-item, the first item of a section can't be one, and a parent with
// sub-items stays top-level (so it only lands between groups).
function dragItem(note, i, row, e) {
  e.preventDefault();
  const { items } = note;
  const it = items[i];
  let end = i + 1;
  if (it.level === 0) while (end < items.length && items[end].level === 1) end++;
  const block = items.slice(i, end);
  const hasSubs = block.length > 1;
  const list = row.parentElement;
  const inBlock = (r) => block.includes(items[r.dataset.i]);
  const rows = [...list.children].filter((r) => !inBlock(r));
  [...list.children].filter(inBlock).forEach((r) => r.classList.add('dragging'));
  const line = document.createElement('div');
  line.className = 'drop-line';
  const grip = e.currentTarget;
  grip.setPointerCapture(e.pointerId);
  const startX = e.clientX;
  let drop = null;

  const move = (e) => {
    let k = rows.filter((r) => {
      const b = r.getBoundingClientRect();
      return b.top + b.height / 2 < e.clientY;
    }).length;
    if (hasSubs) while (rows[k]?.classList.contains('sub')) k++;
    const above = rows[k - 1];
    const below = rows[k];
    const dx = e.clientX - startX;
    let level = dx > 24 ? 1 : dx < -24 ? 0 : it.level;
    if (hasSubs || !above) level = 0;
    else if (below?.classList.contains('sub')) level = 1;
    drop = { above: above && items[above.dataset.i], below: below && items[below.dataset.i], level };
    line.classList.toggle('sub', level === 1);
    list.insertBefore(line, below ?? null);
  };
  const done = (commit) => () => {
    grip.removeEventListener('pointermove', move);
    grip.removeEventListener('pointerup', onUp);
    grip.removeEventListener('pointercancel', onCancel);
    grip.removeEventListener('lostpointercapture', onCancel);
    if (commit && drop) {
      items.splice(i, block.length);
      block[0].level = drop.level;
      // A sub-item goes right after the row above it (same parent, or first
      // sub-item of that parent); a top-level item goes right before the row below.
      const at =
        drop.level === 1 ? items.indexOf(drop.above) + 1 : drop.below ? items.indexOf(drop.below) : items.length;
      items.splice(at, 0, ...block);
      save(note);
    }
    renderBody(note);
  };
  const onUp = done(true);
  const onCancel = done(false);
  grip.addEventListener('pointermove', move);
  grip.addEventListener('pointerup', onUp);
  grip.addEventListener('pointercancel', onCancel);
  grip.addEventListener('lostpointercapture', onCancel);
}

// Marking a parent marks (or unmarks) all its sub-items with it.
function toggleItem(note, i) {
  const { items } = note;
  const done = !items[i].done;
  items[i].done = done;
  if (items[i].level === 0) {
    for (let j = i + 1; j < items.length && items[j].level === 1; j++) items[j].done = done;
  }
  renderBody(note);
  save(note);
}

function itemKey(note, i, input, e) {
  const { items } = note;
  const it = items[i];

  if (e.key === 'ArrowUp' || e.key === 'ArrowDown') {
    // Up/Down always jump to the item above or below, cursor at its end,
    // in on-screen order, never between wrapped lines.
    if (e.shiftKey || e.altKey || e.metaKey) return;
    const up = e.key === 'ArrowUp';
    e.preventDefault();
    const all = [...note.el.querySelectorAll('.body .text')];
    const next = all[all.indexOf(input) + (up ? -1 : 1)];
    if (!next) return;
    next.focus();
    next.setSelectionRange(next.value.length, next.value.length);
    return;
  }
  if (it.done) return; // marked items are read-only

  if (e.key === 'Enter') {
    // New item below, taking the text after the cursor. On a parent that has
    // sub-items, the new item becomes its first sub-item.
    e.preventDefault();
    const caret = input.selectionStart;
    const rest = it.text.slice(caret);
    it.text = it.text.slice(0, caret);
    const level = it.level === 0 && items[i + 1]?.level === 1 ? 1 : it.level;
    items.splice(i + 1, 0, { text: rest, done: false, level });
    renderBody(note, { i: i + 1, caret: 0 });
    save(note);
  } else if (e.key === 'Tab') {
    // Tab nests one level only, under an unmarked parent; Shift+Tab un-nests.
    e.preventDefault();
    const p = parentOf(items, i);
    if (e.shiftKey) {
      if (it.level === 0) return;
      it.level = 0;
    } else {
      if (it.level === 1 || p === -1 || items[p].done) return;
      it.level = 1;
    }
    renderBody(note, { i, caret: input.selectionStart });
    save(note);
  } else if (e.key === 'Backspace' && it.text === '') {
    const active = items.map((x, j) => (x.done ? -1 : j)).filter((j) => j !== -1);
    if (active.length === 1) return;
    e.preventDefault();
    const pos = active.indexOf(i);
    removeItem(note, i);
    const prev = active[pos - 1];
    renderBody(note, prev !== undefined ? { i: prev } : { i: active[pos + 1] - 1, caret: 0 });
    save(note);
  }
}

// Removes just this item (its sub-items stay, under the parent above it).
function removeItem(note, i) {
  const { items } = note;
  items.splice(i, 1);
  // A removed parent's sub-items with no parent left above become top-level.
  for (let j = 0; j < items.length && items[j].level === 1; j++) items[j].level = 0;
}

// Footer button in checkbox mode: deletes every marked item, no confirmation.
function clearDone(note) {
  for (let i = note.items.length - 1; i >= 0; i--) if (note.items[i].done) removeItem(note, i);
  renderBody(note);
  save(note);
}

function deleteNote(note) {
  if (!confirm('Delete this note?')) return;
  removeNote(note);
}

function removeNote(note) {
  notes.splice(notes.indexOf(note), 1);
  clearTimeout(note.timer);
  deleted.add(note.id);
  send(note, () => db.from('notes').delete().eq('id', note.id));
  render();
}

// --- Mac: free-form canvas ---

const onCanvas = (n) => n.el?.parentElement === canvas;

// Would a new note at x, y overlap note n (at n's current size)?
const overlaps = (x, y, n) =>
  x < n.x + n.el.offsetWidth + GAP &&
  x + NOTE_W + GAP > n.x &&
  y < n.y + n.el.offsetHeight + GAP &&
  y + NOTE_H + GAP > n.y;

// First free spot scanning rows from the top-left of the visible canvas.
// If the canvas is full, falls back to a cascade from the top-left.
function findSpot() {
  const placed = notes.filter(onCanvas);
  const maxX = canvas.clientWidth - NOTE_W - STEP;
  const maxY = canvas.clientHeight - NOTE_H - STEP;
  for (let y = STEP; y <= maxY; y += STEP) {
    for (let x = STEP; x <= maxX; x += STEP) {
      if (!placed.some((n) => overlaps(x, y, n))) return { x, y };
    }
  }
  const offset = STEP + (placed.length % 10) * STEP;
  return { x: offset, y: offset };
}

// Notes added on the iPhone have no position yet: they get the first free
// spot once everything already placed is on the canvas.
function renderCanvas() {
  canvas.replaceChildren();
  notes.filter((n) => n.x !== null).forEach(noteEl);
  notes.filter((n) => n.x === null).forEach((n) => {
    Object.assign(n, findSpot());
    noteEl(n);
    save(n);
  });
}

function noteEl(note) {
  const el = document.createElement('div');
  el.className = 'note editor';
  el.innerHTML = EDITOR_HTML + EDGES.map((dir) => `<div class="handle ${dir}" data-dir="${dir}"></div>`).join('');
  canvas.append(el);
  mountEditor(note, el);
  layout(note);
  makeDraggable(note);
  makeResizable(note);
}

function layout(note) {
  const s = note.el.style;
  s.left = `${note.x}px`;
  s.top = `${note.y}px`;
  s.width = `${note.w}px`;
  s.minHeight = `${NOTE_H}px`;
  s.height = note.h ? `${note.h}px` : '';
  s.maxHeight = note.h ? 'none' : '';
  s.zIndex = note.z || '';
}

function addNote() {
  const note = { ...newNote(), ...findSpot() };
  notes.push(note);
  noteEl(note);
  save(note);
}

let topZ = 0;

function makeDraggable(note) {
  const { el } = note;
  el.addEventListener('pointerdown', (e) => {
    // Text fields, checkboxes, buttons and resize handles keep their own clicks.
    if (e.target.closest('input, textarea, button, .handle')) return;
    const dx = e.clientX - note.x;
    const dy = e.clientY - note.y;
    // Bring to front with z-index, not by moving the element in the DOM:
    // a DOM move drops the pointer capture (see CORRECTIONS.md 1-2).
    note.z = ++topZ;
    layout(note);
    el.setPointerCapture(e.pointerId);
    el.classList.add('dragging');

    const move = (e) => {
      note.x = Math.min(Math.max(e.clientX - dx, 0), canvas.clientWidth - el.offsetWidth);
      note.y = Math.min(Math.max(e.clientY - dy, 0), canvas.clientHeight - el.offsetHeight);
      layout(note);
    };
    const up = () => {
      save(note);
      el.classList.remove('dragging');
      el.removeEventListener('pointermove', move);
      el.removeEventListener('pointerup', up);
      el.removeEventListener('pointercancel', up);
      el.removeEventListener('lostpointercapture', up);
    };
    el.addEventListener('pointermove', move);
    el.addEventListener('pointerup', up);
    el.addEventListener('pointercancel', up);
    el.addEventListener('lostpointercapture', up);
  });
}

// Resize from any edge or corner, never below the default size or past the
// canvas edges. Once the height has been dragged, it is fixed: the note stops
// growing with its content and the body scrolls instead. Releasing at the
// minimum height makes it grow with its content again.
const EDGES = ['n', 's', 'e', 'w', 'ne', 'nw', 'se', 'sw'];
const clamp = (v, min, max) => Math.min(Math.max(v, min), max);

function makeResizable(note) {
  const { el } = note;
  el.querySelectorAll('.handle').forEach((handle) => {
    const dir = handle.dataset.dir;
    handle.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      const start = { px: e.clientX, py: e.clientY, x: note.x, y: note.y, w: el.offsetWidth, h: el.offsetHeight };
      note.z = ++topZ;
      layout(note);
      handle.setPointerCapture(e.pointerId);

      const move = (e) => {
        const dx = e.clientX - start.px;
        const dy = e.clientY - start.py;
        if (dir.includes('e')) {
          note.w = clamp(start.w + dx, NOTE_W, canvas.clientWidth - start.x);
        } else if (dir.includes('w')) {
          note.w = clamp(start.w - dx, NOTE_W, start.x + start.w);
          note.x = start.x + start.w - note.w;
        }
        if (dir.includes('s') || dir.includes('n')) {
          note.h = dir.includes('s')
            ? clamp(start.h + dy, NOTE_H, canvas.clientHeight - start.y)
            : clamp(start.h - dy, NOTE_H, start.y + start.h);
          if (dir.includes('n')) note.y = start.y + start.h - note.h;
        }
        layout(note);
      };
      const up = () => {
        if (note.h && note.h <= NOTE_H) {
          note.h = null;
          layout(note);
        }
        save(note);
        handle.removeEventListener('pointermove', move);
        handle.removeEventListener('pointerup', up);
        handle.removeEventListener('pointercancel', up);
        handle.removeEventListener('lostpointercapture', up);
      };
      handle.addEventListener('pointermove', move);
      handle.addEventListener('pointerup', up);
      handle.addEventListener('pointercancel', up);
      handle.addEventListener('lostpointercapture', up);
    });
  });
}

addBtn.addEventListener('click', addNote);

// --- iPhone: list of cards, tap one to open it full screen ---

const listScreen = document.getElementById('list');
const cardsEl = document.getElementById('cards');
const cardScreen = document.getElementById('card');
const cardEditor = document.getElementById('card-editor');
const phoneAdd = document.getElementById('phone-add');
const scrim = document.getElementById('scrim');
const menu = document.getElementById('menu');
const menuDelete = document.getElementById('menu-delete');
const PREVIEW = 5; // items (or lines) shown on a card
const LONG_PRESS = 500; // ms

document.getElementById('back').innerHTML = svg('back');
document.getElementById('back').addEventListener('click', showList);
menuDelete.innerHTML = `Delete ${svg('trash')}`;

function showList() {
  closeMenu();
  cardScreen.hidden = true;
  listScreen.hidden = false;
  phoneAdd.hidden = false;
  cardsEl.replaceChildren(...notes.map(cardEl));
}

let cardNote = null; // note open on the card screen

function openCard(note) {
  cardNote = note;
  listScreen.hidden = true;
  phoneAdd.hidden = true;
  cardScreen.hidden = false;
  cardEditor.innerHTML = EDITOR_HTML;
  mountEditor(note, cardEditor);
}

// View-only card: title and a preview of the first 5 lines (plain text, blank
// lines skipped) or the first 5 unmarked items (checkbox mode).
function cardEl(note) {
  const card = document.createElement('div');
  card.className = 'card';
  const title = document.createElement('div');
  title.className = `title${note.title ? '' : ' empty'}`;
  title.textContent = note.title || 'Title';
  card.append(title);

  const preview = [];
  if (note.mode === 'text') {
    for (const line of note.text.split('\n').filter((l) => l.trim()).slice(0, PREVIEW)) {
      const row = document.createElement('div');
      row.className = 'line';
      row.textContent = line;
      preview.push(row);
    }
  } else {
    note.items.forEach((it, i) => {
      if (it.done || !it.text.trim() || preview.length === PREVIEW) return;
      const row = document.createElement('div');
      row.className = `item${isNested(note.items, i) ? ' sub' : ''}`;
      row.innerHTML = '<span class="box"></span><span class="text"></span>';
      row.querySelector('.text').textContent = it.text;
      preview.push(row);
    });
  }
  if (preview.length) card.append(document.createElement('hr'), ...preview);

  // Tap opens the card; press and hold opens the menu instead.
  let timer;
  let held = false;
  let start;
  card.addEventListener('pointerdown', (e) => {
    held = false;
    start = { x: e.clientX, y: e.clientY };
    timer = setTimeout(() => {
      held = true;
      openMenu(note, card);
    }, LONG_PRESS);
  });
  card.addEventListener('pointermove', (e) => {
    if (start && Math.hypot(e.clientX - start.x, e.clientY - start.y) > 10) clearTimeout(timer);
  });
  for (const type of ['pointerup', 'pointerleave', 'pointercancel']) {
    card.addEventListener(type, () => clearTimeout(timer));
  }
  card.addEventListener('click', () => {
    if (!held) openCard(note);
  });
  card.addEventListener('contextmenu', (e) => e.preventDefault());
  return card;
}

// Menu under the card (above it if there's no room below). Delete here is
// immediate: the long press and menu are already the deliberate step.
function openMenu(note, card) {
  const phone = card.closest('.phone').getBoundingClientRect();
  const c = card.getBoundingClientRect();
  scrim.hidden = false;
  menu.hidden = false;
  const below = c.bottom - phone.top + 6;
  menu.style.top = `${below + menu.offsetHeight > phone.height ? c.top - phone.top - 6 - menu.offsetHeight : below}px`;
  menu.style.right = `${phone.right - c.right}px`;
  menuDelete.onclick = () => removeNote(note);
}

function closeMenu() {
  scrim.hidden = true;
  menu.hidden = true;
}
scrim.addEventListener('pointerdown', closeMenu);

phoneAdd.addEventListener('click', () => {
  const note = newNote();
  notes.push(note);
  save(note);
  openCard(note);
  cardEditor.querySelector('.title').focus();
});

// --- iPhone Home Screen widget (large) ---
// Up to WIDGET_LISTS checkbox lists, as cards in a 2×2 grid on a dotted
// background: each card has its title, then its unmarked top-level items as
// one pill per row, as many as fit in the card (long items are cut to the
// pill width). A round badge right of the title counts all those items. Sub-items, plain text notes and
// lists with nothing left to do are left out; lists past the first 4 become
// "+N more lists". Tapping a card opens that note.

const homeScreen = document.getElementById('home');
const widget = document.getElementById('widget');
const WIDGET_LISTS = 4; // 2×2 grid
let openOnLaunch = null; // note to open when the app comes up from the widget

function showHome() {
  closeMenu();
  listScreen.hidden = true;
  cardScreen.hidden = true;
  phoneAdd.hidden = true;
  const cards = notes.filter((n) => n.mode === 'checklist').map(widgetCard).filter(Boolean);
  const shown = cards.slice(0, WIDGET_LISTS);
  const hidden = cards.length - shown.length;
  widget.replaceChildren(...shown.map((c) => c.el));
  widget.classList.toggle('has-more', hidden > 0);
  if (hidden) {
    const more = document.createElement('div');
    more.className = 'widget-more';
    more.textContent = `+${hidden} more list${hidden === 1 ? '' : 's'}`;
    widget.append(more);
  }
  if (!cards.length) widget.innerHTML = '<div class="widget-empty"><div><b>All done!</b><br>Nothing left on your lists.</div></div>';
  for (const c of shown) while (c.shown > 1 && c.el.scrollHeight > c.el.clientHeight) c.show(c.shown - 1);
}

function widgetCard(note) {
  const todo = note.items.filter((it, i) => !it.done && it.text.trim() && !isNested(note.items, i));
  if (!todo.length) return null;
  const el = document.createElement('div');
  el.className = 'widget-card';
  el.addEventListener('click', () => {
    openOnLaunch = note;
    location.hash = '#iphone';
  });
  // Shows the title with a count of its items, then the first n pills.
  const card = {
    el,
    shown: 0,
    show(n) {
      card.shown = n;
      const head = document.createElement('div');
      head.className = 'head';
      const title = document.createElement('div');
      title.className = `title${note.title ? '' : ' empty'}`;
      title.textContent = note.title || 'Title';
      const count = document.createElement('div');
      count.className = 'count';
      count.textContent = todo.length;
      head.append(title, count);
      const pills = todo.slice(0, n).map((it) => {
        const pill = document.createElement('div');
        pill.className = 'pill';
        pill.textContent = it.text;
        return pill;
      });
      el.replaceChildren(head, ...pills);
    },
  };
  card.show(todo.length); // showHome then drops pills until the card fits
  return card;
}

// --- Sync: every note is a row in Supabase (supabase/schema.sql) ---
// A change saves shortly after it's made; changes from other devices arrive
// over Realtime. If two devices change the same note, the last save wins.

const db = supabase.createClient(
  'https://pgwitomfqzskpilqiklr.supabase.co',
  'sb_publishable_72x2Nmm-9RHHzrm956unPA_jgDc-F3o',
);
const SAVE_DELAY = 500; // ms after the last change
const deleted = new Set(); // ids deleted here, so late echoes of their saves are ignored
let loaded = false;

// The saved fields of a note (or a row), in a fixed order so two can be compared.
const rowOf = (n) => ({
  id: n.id,
  title: n.title,
  mode: n.mode,
  text: n.text,
  items: n.items.map(({ text, done, level }) => ({ text, done, level })),
  x: n.x,
  y: n.y,
  w: n.w,
  h: n.h,
  z: n.z,
});
const unsaved = (note) => note.timer || note.sending;

function save(note) {
  clearTimeout(note.timer);
  note.timer = setTimeout(() => {
    note.timer = null;
    send(note, () => db.from('notes').upsert(rowOf(note)));
  }, SAVE_DELAY);
}

// Requests for one note go out one at a time, in order.
function send(note, request) {
  note.sending = (note.sending || 0) + 1;
  note.queue = (note.queue || Promise.resolve())
    .then(request)
    .then(({ error }) => {
      if (error) throw error;
    })
    .catch((e) => console.error('Sync failed:', e.message))
    .finally(() => note.sending--);
}

// A row from the database: a new note, a change made on another device, or an
// echo of a save from here. Echoes, and rows for notes with changes still
// being saved here, are ignored. Returns the note if it changed.
function applyRow(row) {
  if (deleted.has(row.id)) return null;
  let note = notes.find((n) => n.id === row.id);
  if (note && (unsaved(note) || JSON.stringify(rowOf(note)) === JSON.stringify(rowOf(row)))) return null;
  if (!note) notes.push((note = {}));
  Object.assign(note, rowOf(row));
  topZ = Math.max(topZ, note.z);
  return note;
}

// Shows a note that changed (or was deleted) on another device, leaving the
// rest of the view alone, so a note being edited here keeps its cursor.
function showChange(note, gone) {
  if (!loaded) return;
  if (view() === 'widget') return showHome();
  if (view() === 'iphone') {
    if (!cardScreen.hidden && cardNote === note) return gone ? showList() : openCard(note);
    if (!listScreen.hidden) showList();
    return;
  }
  const old = onCanvas(note) && note.el;
  if (!gone) {
    if (note.x === null) {
      Object.assign(note, findSpot());
      save(note);
    }
    noteEl(note);
  }
  if (old) old.remove();
}

// Loads every note; again each time Realtime (re)connects, e.g. after the Mac
// wakes from sleep, to catch up on changes missed while disconnected.
async function load() {
  const { data, error } = await db.from('notes').select().order('created_at');
  if (error) return console.error('Sync failed:', error.message);
  const ids = new Set(data.map((row) => row.id));
  const changed = data.map(applyRow).filter(Boolean);
  const gone = notes.filter((n) => !ids.has(n.id) && !unsaved(n));
  gone.forEach((n) => notes.splice(notes.indexOf(n), 1));
  if (!loaded) {
    loaded = true;
    return route();
  }
  changed.forEach((n) => showChange(n));
  gone.forEach((n) => showChange(n, true));
}

db.channel('notes')
  .on('postgres_changes', { event: '*', schema: 'public', table: 'notes' }, ({ eventType, new: row, old }) => {
    if (eventType !== 'DELETE') {
      const note = applyRow(row);
      if (note) showChange(note);
      return;
    }
    const note = notes.find((n) => n.id === old.id);
    if (!note) return;
    notes.splice(notes.indexOf(note), 1);
    showChange(note, true);
  })
  .subscribe((status) => status === 'SUBSCRIBED' && load());

// --- Prototype switch between the Mac, iPhone and widget views (same notes) ---

const macView = document.getElementById('mac-view');
const phoneView = document.getElementById('phone-view');
const view = () => ({ '#iphone': 'iphone', '#widget': 'widget' })[location.hash] || 'mac';

function render() {
  if (view() === 'mac') return renderCanvas();
  if (view() === 'widget') return showHome();
  showList();
  if (openOnLaunch) openCard(openOnLaunch);
  openOnLaunch = null;
}

function route() {
  macView.hidden = view() !== 'mac';
  phoneView.hidden = view() === 'mac';
  homeScreen.hidden = view() !== 'widget';
  document.querySelectorAll('.proto a').forEach((a) => a.classList.toggle('on', a.hash === `#${view()}`));
  render();
}
addEventListener('hashchange', route);
load();
