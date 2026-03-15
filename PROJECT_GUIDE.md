# Project Guide

## 1. What this project solves

The original code contains many separate `Pbind` patterns with fixed note lists. That approach works for sketching, but it makes live harmonic control difficult.

This refactor introduces:
- a **single engine object**
- a **shared harmonic state**
- a **MIDI layer**
- reusable **performance scenes**

## 2. How the engine works

### Audio layer
- `\sunDroneLP`: low-pass drone voice
- `\sunDroneHP`: high-pass drone voice
- `\sunReverb`: reverb return synth

### Harmonic layer
- stores the active root note
- stores the active chord type
- builds a chord as MIDI notes
- expands the chord through octave spread

### Pattern layer
- `bassPattern`: low register material
- `midPattern`: chord cloud material
- `arpPattern`: high rhythmic texture

### Control layer
- root note control from one played note
- full chord detection from multiple notes
- CC control for amplitude, density, attack, release, and reverb

## 3. Why this is scalable

Instead of creating many independent variables such as `~drone1`, `~drone2`, `~drone3`, everything is now centralized in one class:

- easier debugging
- easier saving and recalling scenes
- easier extension with OSC, HID, GUI, or other controllers

## 4. Script-by-script explanation

### `00_install_notes.scd`
This script prints useful paths and instructions for Windows. It does not start audio.

### `01_boot_engine.scd`
This is the main startup script. It:
- creates a `SunArpeggios` instance
- boots the server
- allocates buses and groups
- loads SynthDefs
- creates the reverb effect
- initializes the default chord

### `02_play_engine.scd`
This starts the three default layers:
- bass
- middle drone cloud
- bright arpeggio

### `03_midi_root_control.scd`
This lets one played MIDI note become the root of the active chord. Example:
- play C4 -> current harmony becomes C minor by default
- play F4 -> current harmony becomes F minor

### `04_midi_chord_detection.scd`
This tracks all held MIDI notes and tries to recognize a chord shape such as:
- major
- minor
- diminished
- augmented
- sus2
- sus4
- dominant 7th
- major 7th
- minor 7th

When detected, the engine updates the current harmony.

### `05_minilab3_mapping.scd`
This maps your MiniLab 3 controls to the engine.

Default example mapping in the script:
- CC 21 -> amplitude
- CC 22 -> density
- CC 23 -> attack
- CC 24 -> release
- CC 25 -> LPF floor
- CC 26 -> LPF ceiling
- CC 31 -> reverb mix

You can edit those values to match your Arturia user map.

### `06_scene_examples.scd`
This gives a few ready-made musical states to test the engine quickly:
- dark drone scene
- wide ambient scene
- bright arpeggio scene
- suspended harmony scene

### `07_cleanup.scd`
This stops all patterns and frees MIDI definitions.

## 5. First test on Windows

1. Connect MiniLab 3 by USB.
2. Open Arturia MIDI Control Center and confirm it is visible.
3. Close software that may lock the MIDI port.
4. Open SuperCollider.
5. Run `00_install_notes.scd`.
6. Recompile the class library.
7. Run `01_boot_engine.scd`.
8. Run `02_play_engine.scd`.
9. Run `03_midi_root_control.scd`.
10. Play notes on MiniLab 3.

## 6. Important note about MIDI ports

On Windows, MIDI device names may vary depending on drivers and USB order. For that reason, the scripts first print all MIDI sources. If needed, you can restrict `MIDIdef` or `MIDIFunc` to a specific source later.

## 7. Next extension ideas

- scene saving to disk
- OSC control from another machine
- GUI window for live performance
- scale quantization modes
- alternate drone synth engines
- external clock sync
