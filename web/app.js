const canvas = document.getElementById('canvas');
const themeBtn = document.getElementById('theme');
const addBtn = document.getElementById('add');

// Theme: starts from the system setting, then the toggle flips it.
// The icon shows the mode a click switches to.
const ICONS = {
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
  moon: '<path d="M20 14.5A8 8 0 0 1 9.5 4 8 8 0 1 0 20 14.5z"/>',
};
const root = document.documentElement;
function setTheme(theme) {
  root.dataset.theme = theme;
  themeBtn.innerHTML = `<svg viewBox="0 0 24 24">${ICONS[theme === 'dark' ? 'sun' : 'moon']}</svg>`;
}
setTheme(matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
themeBtn.addEventListener('click', () => setTheme(root.dataset.theme === 'dark' ? 'light' : 'dark'));

// Notes
const NOTE_W = 200;
const NOTE_H = 150;
const GAP = 16; // minimum space kept between a new note and existing ones
const STEP = 24; // grid the empty-space search walks, matches the dot grid
const notes = []; // { el, x, y }

const overlaps = (x, y, n) =>
  x < n.x + NOTE_W + GAP && x + NOTE_W + GAP > n.x && y < n.y + NOTE_H + GAP && y + NOTE_H + GAP > n.y;

// First free spot scanning rows from the top-left of the visible canvas.
// If the canvas is full, falls back to a cascade from the top-left.
function findSpot() {
  const maxX = canvas.clientWidth - NOTE_W - STEP;
  const maxY = canvas.clientHeight - NOTE_H - STEP;
  for (let y = STEP; y <= maxY; y += STEP) {
    for (let x = STEP; x <= maxX; x += STEP) {
      if (!notes.some((n) => overlaps(x, y, n))) return { x, y };
    }
  }
  const offset = STEP + (notes.length % 10) * STEP;
  return { x: offset, y: offset };
}

function place(note) {
  note.el.style.left = `${note.x}px`;
  note.el.style.top = `${note.y}px`;
}

function addNote() {
  const el = document.createElement('div');
  el.className = 'note';
  el.style.width = `${NOTE_W}px`;
  el.style.height = `${NOTE_H}px`;
  const note = { el, ...findSpot() };
  notes.push(note);
  place(note);
  canvas.append(el);
  makeDraggable(note);
}

let topZ = 0;

function makeDraggable(note) {
  const { el } = note;
  el.addEventListener('pointerdown', (e) => {
    const dx = e.clientX - note.x;
    const dy = e.clientY - note.y;
    // Bring to front with z-index, not by moving the element in the DOM:
    // a DOM move drops the pointer capture (see CORRECTIONS.md 1-2).
    el.style.zIndex = ++topZ;
    el.setPointerCapture(e.pointerId);
    el.classList.add('dragging');

    const move = (e) => {
      note.x = Math.min(Math.max(e.clientX - dx, 0), canvas.clientWidth - NOTE_W);
      note.y = Math.min(Math.max(e.clientY - dy, 0), canvas.clientHeight - NOTE_H);
      place(note);
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

addBtn.addEventListener('click', addNote);
