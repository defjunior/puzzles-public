# Puzzle systems source

All six puzzle implementations from puzzles, kept private for review: Hitori, Minesweeper, Nonograms, Queens, Rooks and Sudoku. Queens and Rooks are chess-piece puzzles, not a full chess game or chess tactics engine.

- Hitori: grid generation, blocked-cell rules and connected unblocked cells, with its original `Gen.lua` search/generator.
- Minesweeper: safe first reveal, mine placement, flood reveal, flags and chord interactions, including N-dimensional boards.
- Nonograms: procedural masks, row/column run clues, starter hints and interaction checks.
- Queens: generated regions, queen placements, conflict checks and N-dimensional boards.
- Rooks: rook placements, white-piece clues and conflict/solution checks.
- Sudoku: solved-grid generation, clue removal, digit entry and conflict checks.
- `NDimensionalBoard.lua`: dimension/index mapping, slice positioning and board construction interface.

Actual generation, rule checks and session interfaces remain. Short comments mark removed authored defaults, colors, cosmetic identifiers/service methods, extra-board presets, dialogue and Hitori's fallback sample grid. These omissions are deliberate, not working replacement implementations. Extra N-dimensional board preset lists are empty; callers must provide configuration to exercise that retained code.

## Limits

This is a source showcase, not a standalone Roblox game. The game modules still need the original BoardClass, Roblox services/types, scene origins, some Framework wiring and presentation assets. Admin tooling, services/bootstrap, models, skins, rewards and authored puzzle samples are not bundled. Omitted configuration/visual values must be supplied or presentation wiring adapted before running these modules. Cosmetic methods are explicit no-op stubs.

Hitori's deadlines/best-candidate fallback mean a uniqueness request is not a guarantee. Its session module can now return early if procedural generation fails because the authored fallback sample was removed. Sudoku removes clues from a generated solution without a uniqueness solver; its input checks compare with that generated answer. Nonograms checks against its generated mask rather than proving clue uniqueness. Queens/Rooks are chess-piece placement puzzles with their own rules, not chess move engines. None of these omissions or limitations were repaired or represented as passing tests.

No Roblox execution, solver regression, uniqueness benchmark or performance testing was performed. N-dimensional sizes grow quickly; no large-board memory/performance guarantee is claimed. See `source-manifest.json` for source/output hashes and omissions. Original puzzles source remains untouched and private. Original git history is not imported. Private, no license; owner review and a full extraction-history audit are required before any public release.
