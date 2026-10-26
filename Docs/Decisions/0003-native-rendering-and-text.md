# ADR 0003: Native raster and native shaping

Accepted. Implement the portable renderer contract with a retained Core Graphics bitmap and Core Text. This replaces the design document's proposed Skia evaluation default per the user's native-per-platform decision.

All initial rendering stays on the UI executor. Immutable complete scenes, surface epochs, backing revisions, and damage-base tags preserve a future worker/backend boundary. No claim is made about confirmed display presentation. Partial raster redraw always uses preserved backing pixels, never presumed window-buffer contents.

Core Text supplies shaping, fallback, width-constrained paragraphs, baselines, and text-position geometry. The headless text service is a deterministic test double and is never used for native applications. OS-specific text snapshots are not universal pixel baselines.
