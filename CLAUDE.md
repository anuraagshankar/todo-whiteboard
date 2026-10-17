# Whiteboard Todos

Personal whiteboard-style notes and todo app: a free-form canvas where I place and arrange notes and todo lists, rather than a plain list.

## Platforms
- **Mac (primary):** the full whiteboard experience. This is where I'll use it most.
- **iPhone (secondary):** a simpler version for viewing and quick edits. Its most important part is the Home Screen widget, which should always show my current todos at a glance.
- Both devices share the same data: an edit on one must appear on the other.

## Constraints
- iPhone is an SE 2020 (old, low-end). The iPhone app and widget must be lightweight, fast and minimal: no unnecessary dependencies, animations or features.
- Sync via Supabase (free plan): the web app and the Apple apps all read and write the same Supabase database. No custom backend of our own.

## Structure
- `web/`: prototype for iterating on UI/UX on my Mac, including mockups of the iPhone app and widget. Performance doesn't matter here; speed of iteration does.
- `apple/`: one multiplatform SwiftUI project with the Mac app, the iPhone app and the widget (WidgetKit), sharing data and model code.

## Workflow
1. Build and refine the UI in `web/` until I approve it.
2. Only then build `apple/`, treating the web app as the source of truth for design and behavior, and checking every item in `CORRECTIONS.md` (corrections I made while reviewing the web app). Match it exactly unless something is impossible or inefficient on macOS/iOS; if so, tell me rather than silently changing it.
3. Always prefer the lightest, most efficient implementation, especially on iPhone.

## Instructions
- Only implement the exact things the user has asked for, no extra features.
- If anything extra is needed, the user will explicitly ask for it.