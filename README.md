# SunArpeggios Quark

SunArpeggios is a SuperCollider Quark-oriented project for **generative drones, adaptive arpeggios, and live harmonic control by MIDI**.

This version is designed for:
- **SuperCollider 3.13.0**
- **Windows**
- **Arturia MiniLab 3 via USB MIDI**

The current design refactors the original idea from *The Sun Arpeggios* into a structure that is easier to understand, extend, and perform live with. The original documentation describes the project as a generative ambient system based on drones, randomness in pitch selection, and reverb-based space processing. It also emphasizes live manipulation of parameters such as `freq`, `Prand`, and `Pseq` for expressive performance. fileciteturn1file0L1-L18 fileciteturn1file1L23-L31

## Main goals of this version

- Replace hard-coded pitch lists with a **dynamic chord engine**
- Allow chord changes from **keyboard notes or detected played chords**
- Map external controls from the **MiniLab 3** to sound parameters
- Keep the code split into **small, readable scripts**
- Make the project scalable as a **Quark-like reusable package**

## Folder structure

```text
SunArpeggiosQuark/
├── Quark
├── README.md
├── PROJECT_GUIDE.md
├── Classes/
│   └── SunArpeggios.sc
├── HelpSource/
│   └── Classes/
│       └── SunArpeggios.schelp
├── SynthDefs/
│   └── sun_synthdefs_reference.scd
└── Examples/
    ├── 00_install_notes.scd
    ├── 01_boot_engine.scd
    ├── 02_play_engine.scd
    ├── 03_midi_root_control.scd
    ├── 04_midi_chord_detection.scd
    ├── 05_minilab3_mapping.scd
    ├── 06_scene_examples.scd
    └── 07_cleanup.scd
```

## Installation on Windows

### Option A: quick test without formal Quark installation

1. Copy the `SunArpeggiosQuark` folder anywhere on your PC.
2. Open SuperCollider.
3. Open the folder scripts from `Examples/` one by one.
4. Evaluate `00_install_notes.scd` first.
5. Recompile the class library if needed: `Language > Recompile Class Library`.
6. Run `01_boot_engine.scd`.

### Option B: install as a Quark-like local extension

1. Find your user extension directory in SuperCollider:
   `Platform.userExtensionDir.postln;`
2. Copy the `SunArpeggiosQuark` folder into that directory.
3. Recompile the class library.
4. Run the scripts from `Examples/`.

## Recommended workflow

1. Boot the server with `01_boot_engine.scd`
2. Start audio with `02_play_engine.scd`
3. Test note-root control with `03_midi_root_control.scd`
4. Test chord detection with `04_midi_chord_detection.scd`
5. Map your MiniLab 3 controls with `05_minilab3_mapping.scd`
6. Try performance presets with `06_scene_examples.scd`
7. Stop and clean with `07_cleanup.scd`

## MIDI notes

This package uses generic MIDI by default, because MiniLab 3 mappings can be changed in **Arturia MIDI Control Center**. That is the best approach for a stable live setup.

The scripts assume this workflow:
- Keys send note on/off messages
- Knobs send CC messages
- Pads can send notes or CC, depending on your user map

You can change all CC numbers in `05_minilab3_mapping.scd`.

## Design philosophy

The original work aims for immersive drones, complex harmonies, and evolving ambient textures driven by controlled randomness and spatial effects. This version preserves that direction while moving the project into a modular live-performance engine. fileciteturn1file1L10-L22
