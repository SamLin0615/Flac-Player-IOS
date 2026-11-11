# FLAC Player for iOS

A local-file FLAC music player built with SwiftUI and a custom Core Audio playback engine.

## Features

- Browse songs, albums, and artists, with persisted library sorting and artwork.
- Create, rename, reorder, and manage playlists; explore Recently Added, Recently Played, and Most Played smart lists.
- Manage the playback queue with Play Next, Add to Queue, reordering, shuffle, and repeat.
- Use a full player with waveform scrubbing, elapsed/remaining time, format badges, lyrics, volume, and AirPlay controls.
- Shape sound with a 10-band parametric EQ, built-in and user presets, preamp, true bypass, and automatic headroom.
- Apply Track or Album ReplayGain with preamp and peak-based clipping protection; ReplayGain defaults to Off.
- Set a sleep timer for 15/30/45/60 minutes or the end of the track, with a fade-out.
- Resume the saved queue, track, position, shuffle, and repeat settings; sessions restore paused.

## Requirements

- Xcode 26 on macOS
- iOS 26.4 or later

Open `flac player.xcodeproj` in Xcode, configure signing for your device, and build and run the app.

## Add music

Music is scanned from the app’s Documents directory. You can:

1. Tap **Import** in the Library tab and select one or more FLAC files.
2. In the **Files** app, copy FLAC files into this app’s folder under **On My iPhone/iPad** (its Documents directory).
3. Connect your device to a Mac and use **Finder → device → Files** to copy FLAC files into the app’s shared Documents directory.

The library refreshes when the app returns to the foreground. Playlists reference Documents-relative paths, so renaming or moving a file changes its identity.

## Architecture

- `flac player/Models/`: song identity, incremental native FLAC metadata parsing, album grouping values, playlists, and play statistics.
- `flac player/ViewModels/MusicLibrary.swift`: scanning, cached album/artist groups, waveform caching, playlist persistence, and smart lists.
- `flac player/AudioEngine/`: `FLACPlayer` coordinates RemoteIO output, an `ExtAudioFile` reader, and `RingBuffer` buffering. `EQEngine` applies biquad filters; supporting managers handle the audio session, Now Playing, and EQ presets.
- `flac player/Views/`: Library, Playlists, and Search tabs, shared song actions, and native player, queue, lyrics, and EQ sheets.

### Threading model

- Playback controls, published UI state, queue edits, persistence, and EQ controls run on the main thread.
- One persistent serial reader queue performs file reads and applies pending seeks, keeping reads and seeks serialized.
- RemoteIO renders buffered audio, applying ReplayGain and EQ; context and EQ publication use non-blocking trylocks on render, while ring buffers retain their existing locks.
- Teardown synchronously stops output, signals the reader, waits for it to exit, and only then disposes the file and replaces buffers.
- The main-thread timer consumes synchronized playback snapshots for UI time, play statistics, and one-shot end-of-track handling.

## Known gaps and verification

**Gapless playback is not yet implemented.** See [Design review §6: Not done yet](docs/DESIGN_REVIEW.md#6-not-done-yet-recommended-next) for remaining work and recommendations.

The overhaul was developed on Linux without Xcode or an iOS SDK. It has not been compiled or run on iOS; a macOS build and device smoke test are required before merge. The project currently has no unit-test target.
