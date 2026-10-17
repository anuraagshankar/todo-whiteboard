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
// { title, mode, text, items, x, y, w, h, z }: x/y are null until it is first
// placed on the Mac canvas, h is null while it grows with its content.
// note.el (and modeBtn/clearBtn) point at whichever editor is showing it.
const NOTE_W = 284; // includes the column reserved for item delete buttons
const NOTE_H = 160; // starting (minimum) height; notes grow with content up to 75% of the page height
const GAP = 16; // minimum space kept between a new note and existing ones
const STEP = 24; // grid the empty-space search walks, matches the dot grid
const notes = [];

const newNote = () => ({ title: '', mode: 'text', text: '', items: [], x: null, y: null, w: NOTE_W, h: null, z: 0 });

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
  title.addEventListener('input', () => (note.title = title.value));
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
    const input = body.querySelector(`[data-i="${focus.i}"]`);
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
  });
  row.append(box, text, remove);
  return row;
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
  } else if (e.key === 'Backspace' && it.text === '') {
    const active = items.map((x, j) => (x.done ? -1 : j)).filter((j) => j !== -1);
    if (active.length === 1) return;
    e.preventDefault();
    const pos = active.indexOf(i);
    removeItem(note, i);
    const prev = active[pos - 1];
    renderBody(note, prev !== undefined ? { i: prev } : { i: active[pos + 1] - 1, caret: 0 });
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
}

function deleteNote(note) {
  if (!confirm('Delete this note?')) return;
  removeNote(note);
}

function removeNote(note) {
  notes.splice(notes.indexOf(note), 1);
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

function openCard(note) {
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
  openCard(note);
  cardEditor.querySelector('.title').focus();
});

// --- Prototype switch between the Mac and iPhone views (same notes) ---

const macView = document.getElementById('mac-view');
const phoneView = document.getElementById('phone-view');
const isPhone = () => location.hash === '#iphone';

function render() {
  if (isPhone()) showList();
  else renderCanvas();
}

function route() {
  macView.hidden = isPhone();
  phoneView.hidden = !isPhone();
  document.querySelectorAll('.proto a').forEach((a) => a.classList.toggle('on', a.hash === (isPhone() ? '#iphone' : '#mac')));
  render();
}
addEventListener('hashchange', route);
route();
