/// The trailing affordance / interaction model for an [InteractiveListTile].
enum InteractiveListTileAction { toggle, bottomSheet, arrow, extended, none }

/// Leading visual for a tile. Trimmed to the two states this design system
/// backs natively: a plain [Icon]/SVG, or nothing.
enum InteractiveListTileIconState { normal, none }

/// Visual interaction state, driven by hover / disabled.
enum InteractiveListTileState { normal, hover, disabled }

/// Content style of a tile: a standard actionable row, or informational text
/// (optionally bulleted).
enum InteractiveListTileType { normal, info, bulletedInfo }
