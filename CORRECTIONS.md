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
