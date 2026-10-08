# Puzzle systems source

Two focused systems from puzzles, kept private for review.

- `src/ServerStorage/Games/Hitori/Gen.lua`: actual constraint validation, bounded solution search and procedural Hitori generation. Rules cover row/column duplicates, adjacent blocked cells and connectivity of unblocked cells.
- `src/ServerStorage/Modules/NDimensionalBoard.lua`: dimension/index mapping, slice positioning and board construction interface.

## What this shows

The Hitori module keeps validation and search separate from the game's sessions/UI. NDimensionalBoard separates logical coordinates from physical board placement. These are the original implementations, with short responsibility comments; no simplified replacement solver or copied puzzle samples are included.

## Limits

A generation request with uniqueness enabled does not guarantee a unique result: the search uses deadlines, and the generator can return its best candidate after the unique-solution check times out or fails. Callers must verify the result independently when uniqueness matters. This is an explicit source limitation, not a passing test claim.

NDimensionalBoard requires Roblox CFrame/Vector3/HttpService and a supplied BoardClass/config. Dimension sizes grow quickly; no large-board memory/performance guarantee is claimed. This extraction does not bundle game sessions, admin tooling, UI, authored board samples, skins, rewards, assets or full bootstrap.

No Roblox execution, solver regression, uniqueness benchmark or performance testing was performed for this extraction. See `source-manifest.json` for file-by-file live comparison and hashes. The original puzzles repo was only switched to private, not edited. Original git history is not imported. Private, no license; owner review and a full extraction-history audit are required before any public release.
