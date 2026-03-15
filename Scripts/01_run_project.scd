(
s.waitForBoot {
    ~sun = SunArpeggios.new(s);

    ~sun.loadSynthDefs;
    ~sun.setupAudio;
    ~sun.setupMidi;
    ~sun.listMidiSources;

    ~sun.setupRootNoteControl(\minor);
    // ~sun.setupChordDetection;

    ~sun.setupMiniLab3DefaultMap;

    ~sun.setChord(60, \minor);
    ~sun.play;

    "Project is running.".postln;
    "Keys change root. Pads change chord type.".postln;
};
)