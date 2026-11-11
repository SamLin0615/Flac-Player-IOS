# Design review: FLAC Player (iOS)

Reviewed against commit `e5aa5b7`. There was no README or written design plan in the repo, so I inferred the intended design from the code: a local-file, audiophile-focused FLAC player with a custom RemoteIO engine, a 10-band parametric EQ, waveform scrubbing, a library, playlists, and a queue.

Severity: **P0** means data loss, a crash, or broken core playback. **P1** means a core listener feature is missing or broken. **P2** means a quality, performance or polish problem.

## 1. Library and data model

| # | Sev | Finding | Resolution in this PR |
|---|-----|---------|-----------------------|
| 1.1 | P0 | `Song.id = UUID()` is regenerated on every scan. Playlists store those IDs, so **every playlist is emptied on relaunch or rescan**. Queue lookups by `firstIndex(of:)` also break after a refresh. | The ID is now the path relative to Documents. This stays stable across launches and app updates. |
| 1.2 | P1 | Metadata keys `track`, `discnumber` and `albumartist` don't exist in CoreAudio's info dictionary (it uses `"track number"` with strings like `"3/12"`), so track and disc numbers were always nil. Album track order fell back to title order. Album artist, disc, lyrics and ReplayGain could not be read. | Added a native FLAC metadata reader (STREAMINFO, VORBIS_COMMENT, PICTURE). It reads only the header blocks. The CoreAudio path is kept as a fallback, with corrected key names. |
| 1.3 | P1 | Albums were grouped by album name alone, so "Greatest Hits" from different artists merged into one album. Artists were keyed by track artist, so featured-artist tracks split an album across artists. | Albums are grouped by (album artist, album). Tracks are ordered by (disc, track, title). |
| 1.4 | P2 | Full-resolution artwork was kept in memory for every song (often 1–3 MB decoded each). | Artwork is downsampled to a 600 px thumbnail at parse time. |
| 1.5 | P2 | The waveform was computed by decoding the **entire file into a single buffer**, which is hundreds of MB for hi-res tracks and a jetsam risk. It was done twice (by the library and by the player). The cache was keyed by absolute container path, which changes on app update, and was rewritten once per song. | Waveforms are now computed with chunked reads into 120 peak bins. There is one implementation, the cache is keyed by relative ID, and saves are batched. |
| 1.6 | P2 | `albums` and `artists` were recomputed (group + sort of the whole library) on every SwiftUI body evaluation. | Both are cached and rebuilt only when `songs` changes. |

## 2. Playback engine

| # | Sev | Finding | Resolution |
|---|-----|---------|------------|
| 2.1 | P0 | `pause()` called `AudioOutputUnitStop` **asynchronously** on a global queue. When skipping tracks, `play()` → `stop()` → `pause()` could run that async stop *after* the new unit was created. The result was silence while the UI showed "playing". | All controls now run on the main thread, and the unit is stopped synchronously. |
| 2.2 | P0 | `stop()` disposed the `ExtAudioFile` while the reader thread could still be inside `ExtAudioFileRead` (use-after-free). Ring buffers were swapped while the render thread could be reading them. | Teardown now stops the unit, signals the reader, waits for it to exit, and only then disposes the file. Each track gets its own playback context. |
| 2.3 | P0 | The end of a track was posted to main from **every** render callback until it was handled, which could skip several tracks. Render also called `DispatchQueue.main.async` and took blocking locks on the real-time thread. | The end of a track is now signalled once per track. Render uses only `trylock` and never dispatches. |
| 2.4 | P1 | Seek called `ExtAudioFileSeek` on another thread concurrently with `ExtAudioFileRead`. Stale pre-seek audio could also play after a seek. | Seeks are serialized through the reader with a generation counter, and render outputs silence during the flush. |
| 2.5 | P1 | `repeatMode` existed but had no UI, and "repeat off" still looped back to the start. Shuffle was destructive (there was no way to un-shuffle), and the queue didn't work with duplicate tracks. | The queue is now index-based with per-entry tokens. Repeat off/all/one behaves correctly, and turning shuffle off restores the original order. |
| 2.6 | P1 | There was no handling for audio interruptions (phone calls, Siri) or route changes, so unplugging headphones kept playing **out of the speaker**. | Interruptions now pause and resume. Losing the old output device pauses playback. Media-services reset is handled. |
| 2.7 | P2 | The audio session was **deactivated between every track**, which briefly hands audio to other apps and makes Now Playing flicker. A 5 ms IO buffer wasted battery for pure playback. | The session is activated once and uses the default IO buffer size. |
| 2.8 | P2 | Now Playing info (including a new `MPMediaItemArtwork`) was rebuilt 10 times per second. | Full info is set once per track. After that, only elapsed time and rate are updated on state changes. Repeat and shuffle remote commands were added. |
| 2.9 | P1 | No "resume where you left off": every launch started empty. | The queue, track, position, shuffle and repeat are saved and restored, paused. |

## 3. EQ

| # | Sev | Finding | Resolution |
|---|-----|---------|------------|
| 3.1 | P0 | Band coefficients were mutated from the main thread while the render thread read them. `setSampleRate` **reallocated the band arrays mid-render**, and files with more than 2 channels indexed out of range. | Coefficients are now published through a lock the render thread only tries. Arrays are fixed in size, and extra channels are bounds-checked. |
| 3.2 | P1 | There was no headroom: a +12 dB boost on mastered material clips hard. | Added Auto Headroom (preamp is reduced by the peak of the combined curve) and a user preamp control. |
| 3.3 | P1 | `EQPresetManager` (in a file misspelled `EQPresentManager.swift`) existed but was never used. There were no built-in presets, and EQ state was lost on relaunch. | Added 15 built-in presets, user presets (save, update, rename, delete), and persisted EQ state. |
| 3.4 | P2 | The graph drew every band with an analog peaking approximation, so the low and high **shelves were drawn wrong**. The "True Phase Response Active" label was inaccurate. | The graph is now computed from the actual biquad coefficients at the file's sample rate. |
| 3.5 | P2 | Bypass also bypassed the preamp only partially. | Bypass is now a true A/B: preamp and bands are both bypassed. |

## 4. UX and navigation

| # | Sev | Finding | Resolution |
|---|-----|---------|------------|
| 4.1 | P1 | The full player had **no visible play/pause, next or previous buttons**. Transport was gesture-only, and tapping anywhere toggled pause, which is easy to do by accident. | Added a standard transport row with shuffle, previous, play/pause, next and repeat. |
| 4.2 | P1 | No elapsed or remaining time. The scrubber was relative-drag only (no tap-to-seek), and its bars were sampled by striding, which aliases. | The scrubber now supports absolute drag and tap-to-seek, shows elapsed and −remaining time, and uses max-pooled bars. |
| 4.3 | P1 | `PlaylistsListView` was never reachable. Its "New Playlist" alert could never open (the binding was derived from an empty string). "Add to Playlist" had no way to create a playlist. | Added a tab bar (Library, Playlists, Search), working create/rename/delete, reordering, and a multi-select "Add Songs" sheet. |
| 4.4 | P1 | No Play Next or Add to Queue anywhere. | Added a context menu and swipe actions on every song, plus menus on albums and playlists. |
| 4.5 | P2 | `NavigationView` wrapped a `NavigationStack`, giving double navigation. The full player used manual screen-height offsets. | Each tab now has its own `NavigationStack`. The mini player sits in `tabViewBottomAccessory`, and the full player is a native sheet. |
| 4.6 | P2 | The format label showed `44kHz` for 44.1 kHz. Volume, AirPlay and lyrics views existed but were never shown. Icon buttons had no accessibility labels. | Fixed the format label, wired up volume, AirPlay and lyrics, and added accessibility labels. |
| 4.7 | P2 | Import accepted one file at a time and only `print`ed errors. | Import now accepts multiple files and shows an error alert. |

## 5. New listener features in this PR

- Smart lists: Recently Added, Recently Played, Most Played. These are backed by play counts, recorded after 30 s or 50 % of a track.
- ReplayGain: Off / Track / Album, with a preamp and peak-based clip protection. It defaults to Off so playback stays bit-perfect.
- Sleep timer: 15, 30, 45 or 60 minutes, or end of track, with a 5 s fade-out.
- Library sorting (title, artist, album, date added), an album grid, and an artist view grouped by album.

## 6. Not done yet (recommended next)

1. **Gapless playback** is the most important missing feature for a serious listener (live albums, classical, concept albums). Each track change currently tears down and rebuilds RemoteIO, which leaves a gap of roughly 100–300 ms. The reader loop now runs per playback context, so the natural next step is to open the next file inside the reader when the current one reaches EOF and the format matches. The ring buffer then carries on without a break, and a frame marker flips the track. When the format differs, it should fall back to today's rebuild. I left this out of this PR because it changes the real-time path and I could not test it on a device here.
2. Sample-rate switching visibility: show the actual hardware rate (`AVAudioSession.sampleRate`) next to the file rate, so the user can tell when iOS is resampling (for example over Bluetooth or with multiple apps).
3. Formats: ALAC, WAV and AIFF are cheap to add, because ExtAudioFile already decodes them.
4. Synced (LRC) lyrics, folder import and library management (deleting files), CarPlay, and widgets.
5. A unit-test target for the metadata reader, queue logic and EQ math. These are pure, testable code, and the project has no test target today.

## Verification status

This was written and reviewed on Linux with no Xcode or iOS SDK. **None of it has been compiled or run yet.** It needs to be built on macOS (Xcode 26, iOS 26.4 SDK) and smoke-tested before merge.
