(
// MIDI debug utility
// Run this file to inspect incoming MIDI notes and CC values.
// Useful for identifying MiniLab 3 pad notes, knob CCs, and fader CCs.

MIDIClient.init;
MIDIIn.connectAll;

"Connected MIDI sources:".postln;
MIDIClient.sources.do { |src, i|
    ("Source " ++ i ++ ": " ++ src.device ++ " | " ++ src.name).postln;
};

MIDIdef.freeAll;

MIDIdef.noteOn(\debugNoteOn, { |vel, note, chan, src|
    ("NOTE ON -> note: " ++ note ++ ", velocity: " ++ vel ++ ", channel: " ++ chan ++ ", source: " ++ src).postln;
});

MIDIdef.noteOff(\debugNoteOff, { |vel, note, chan, src|
    ("NOTE OFF -> note: " ++ note ++ ", velocity: " ++ vel ++ ", channel: " ++ chan ++ ", source: " ++ src).postln;
});

MIDIdef.cc(\debugCC, { |val, cc, chan, src|
    ("CC -> cc: " ++ cc ++ ", value: " ++ val ++ ", channel: " ++ chan ++ ", source: " ++ src).postln;
});

"MIDI debug is active.".postln;
"Move knobs, faders, pads, and keys on the MiniLab 3 to inspect the messages.".postln;
)