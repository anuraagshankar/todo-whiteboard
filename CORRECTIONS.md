# Corrections

Rolling list of corrections and bugs found while reviewing the web prototype. Each one is fixed in `web/`, and must also hold in the `apple/` implementation.

## Dragging notes

1. **Drag must keep going when the cursor leaves the note.** While dragging, moving the cursor faster than the note (or outside its frame) must not stop the drag; the note keeps following the cursor until release.
2. **Releasing outside the note must end the drag.** If the cursor is released while outside the note's frame, the drag ends right there; moving back over the note afterwards must not pick it up again.

   *Web cause (1 and 2):* the note was moved in the DOM to bring it to the front, which dropped its pointer capture, so moves and the release were only seen while the cursor was over the note. Fixed by bringing it to the front with `z-index` instead and ending the drag on `lostpointercapture` too.
   *Apple:* track the drag at the canvas/window level for the whole gesture (not via hover over the note), and always end it on mouse-up wherever it happens.

## Look

3. **The + button matches the current mode**, not its inverse: same surface as the notes (light in light mode, dark in dark mode).
4. **The light/dark toggle is an icon, not text**: a round icon button showing the mode a click switches to (moon in light mode, sun in dark mode).
5. **Checkboxes are outlined, never filled**: a thin gray square outline; when marked, a gray tick inside the same outline (no filled background, unlike the native macOS/iOS checkbox).
6. **Marked items have no "Done" heading**: they sit below a plain horizontal rule, in gray with strikethrough text.
11. **A horizontal rule separates the body from the footer**, the same minimal rule as between the title and the body.

## Note size

7. **Notes are a little wider with larger text** than first built (title 17, body 15; width now 288pt, see 12 and 16).
8. **Notes grow instead of scrolling**: a note's height follows its content, from its starting height up to 75% of the window height; only past that does the body scroll.
14. **A resized height is fixed**: once the user drags a note's height (top/bottom edge or a corner), that height is both its minimum and maximum: it no longer grows with content, the body scrolls instead, and it can be dragged shorter than its content (down to the default size). Resizing only the width leaves the height auto-growing. Releasing a height drag at the minimum (default) height resets this: the note grows with its content again.

## Plain text mode

15. **Tab types a tab character** (replacing any selection) instead of moving focus to the next control. Tabs render 4 spaces wide. It must be a normal text edit: Cmd+Z undoes a typed tab like any other typing (the web version first broke undo by setting the text directly).

## Checkbox items

9. **Up/Down arrows move between items, never within one**: Up always goes to the item above and Down to the item below, with the cursor at the end of that item in both cases, even when the item wraps onto several lines (on-screen order, including into the marked section; nothing happens past the first/last item).
10. **Items word-wrap** onto further lines instead of scrolling sideways on one line; the checkbox stays aligned with the first line. Still one item per "line" in the data: Enter makes a new item, never a line break.
12. **Hover × deletes an item**: notes are a little wider (288pt) to reserve a column at the right of every item that text never flows into. Hovering an item (unmarked or marked) shows an × there (slightly larger than first built, nearly the checkbox's size); clicking it deletes the item outright (not marked done). Its sub-items stay, joining the parent above.
13. **"Delete marked items" footer button, checkbox mode only**: a second button on the left of the footer, next to the mode button, that deletes every marked item at once with no confirmation. Hidden in plain text mode. Its icon is a line-drawn broom (tilted handle, small cap, flared bristles with a wavy bottom edge, no dust); reuse the same path from `web/app.js` (`ICONS.broom`) as a custom symbol/shape.
16. **Item drag grips sit clear of both the checkbox and the note border**: the note's left padding is 16pt (right stays 12pt), and the ⋮⋮ grip sits in that margin with a few points of space on each side (grip too close to the checkbox, then too close to the border, in the first versions). Note width went to 288pt so the text width stayed the same.
