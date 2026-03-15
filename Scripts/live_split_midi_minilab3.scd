(
// ------------------------------------------------------------
// Sun Arpeggios - Live MIDI split performance script
// Low notes -> organ / orchestral bass style
// High notes -> bright fast voice with zero attack
// Velocity -> amplitude
// Note number decides which synth and envelope behavior to use
// ------------------------------------------------------------

s.waitForBoot {

    // --------------------------------------------------------
    // Global state
    // --------------------------------------------------------

    ~sun = ();
    ~sun.activeNotes = IdentityDictionary.new;
    ~sun.lowHighSplit = 60;   // C4 as split point
    ~sun.reverbBus = Bus.audio(s, 2);
    ~sun.sourceGroup = Group.head(s);
    ~sun.fxGroup = Group.after(~sun.sourceGroup);

    // --------------------------------------------------------
    // Reverb
    // --------------------------------------------------------

    SynthDef(\sunMasterReverb, {
        |inBus=0, out=0, mix=0.28, room=0.85, damp=0.45|
        var dry, wet, sig;

        dry = In.ar(inBus, 2);
        wet = FreeVerb.ar(dry, mix, room, damp);
        sig = Limiter.ar(wet, 0.95);

        Out.ar(out, sig);
    }).add;

    // --------------------------------------------------------
    // Low voice
    // Organ / orchestral-bass inspired
    // Slower attack, darker tone, more body
    // --------------------------------------------------------

    SynthDef(\sunLowVoice, {
        |out=0, freq=110, amp=0.15, gate=1, attack=0.08, release=1.8, cutoff=900|
        var env, body, organ, sub, noise, sig;

        env = Env.asr(attack, 1, release).kr(2, gate);

        sub = SinOsc.ar(freq * 0.5, 0, 0.28);

        organ = Mix([
            VarSaw.ar(freq, 0, 0.45, 0.16),
            Pulse.ar(freq * 2, 0.5, 0.08),
            SinOsc.ar(freq, 0, 0.14)
        ]);

        body = Mix([
            Saw.ar(freq * 0.998, 0.08),
            Saw.ar(freq * 1.002, 0.08)
        ]);

        noise = LPF.ar(WhiteNoise.ar(0.01), 250);

        sig = sub + organ + body + noise;
        sig = LPF.ar(sig, cutoff);
        sig = BLowShelf.ar(sig, 120, 0.8, 4);
        sig = LeakDC.ar(sig);
        sig = tanh(sig * 1.4);

        sig = Pan2.ar(sig * env * amp, 0);
        Out.ar(out, sig);
    }).add;

    // --------------------------------------------------------
    // High voice
    // Fast, bright, zero attack
    // Keeps some unstable texture but much cleaner than pure noise
    // --------------------------------------------------------

    SynthDef(\sunHighVoice, {
        |out=0, freq=440, amp=0.08, gate=1, attack=0.0, release=0.25, hpf=1400|
        var env, tone, air, sig;

        env = Env.asr(attack.max(0.0001), 1, release).kr(2, gate);

        tone = Mix([
            Pulse.ar(freq, 0.45, 0.12),
            SinOsc.ar(freq * 2, 0, 0.06),
            VarSaw.ar(freq * 1.01, 0, 0.35, 0.08)
        ]);

        air = Gendy1.ar(1, 1, 1, 1, freq * 0.998, freq * 1.002, 0.03, 0.02) * 0.05;

        sig = tone + air;
        sig = HPF.ar(sig, hpf);
        sig = BPeakEQ.ar(sig, freq.clip(300, 4000), 0.5, 2);
        sig = LeakDC.ar(sig);
        sig = tanh(sig * 1.15);

        sig = Splay.ar([sig, DelayC.ar(sig, 0.02, 0.006)], 0.12);
        Out.ar(out, sig * env * amp);
    }).add;

    s.sync;

    ~sun.reverbSynth = Synth.tail(~sun.fxGroup, \sunMasterReverb, [
        \inBus, ~sun.reverbBus,
        \out, 0,
        \mix, 0.28,
        \room, 0.85,
        \damp, 0.45
    ]);

    // --------------------------------------------------------
    // MIDI setup
    // --------------------------------------------------------

    MIDIClient.init;
    MIDIIn.connectAll;

    "Connected MIDI sources:".postln;
    MIDIClient.sources.do { |src, i|
        ("Source " ++ i ++ ": " ++ src.device ++ " | " ++ src.name).postln;
    };

    MIDIdef.freeAll;

    // --------------------------------------------------------
    // Helper: map MIDI velocity to amplitude
    // Low notes have more body
    // High notes stay lighter
    // --------------------------------------------------------

    ~sun.velocityToAmpLow = { |vel|
        vel.linlin(1, 127, 0.04, 0.22).clip(0.04, 0.22);
    };

    ~sun.velocityToAmpHigh = { |vel|
        vel.linlin(1, 127, 0.01, 0.10).clip(0.01, 0.10);
    };

    // --------------------------------------------------------
    // Note on
    // --------------------------------------------------------

    MIDIdef.noteOn(\sunLiveSplitNoteOn, { |vel, note, chan, src|

        var freq, synth, amp, attack, release;

        // Avoid duplicate synths if same note is retriggered
        if(~sun.activeNotes[note].notNil) {
            ~sun.activeNotes[note].set(\gate, 0);
            ~sun.activeNotes.removeAt(note);
        };

        freq = note.midicps;

        if(note < ~sun.lowHighSplit) {
            amp = ~sun.velocityToAmpLow.(vel);

            // Lower notes have slower attack and longer release
            attack = note.linlin(24, ~sun.lowHighSplit - 1, 0.14, 0.04).clip(0.04, 0.14);
            release = note.linlin(24, ~sun.lowHighSplit - 1, 2.8, 1.2).clip(1.2, 2.8);

            synth = Synth(\sunLowVoice, [
                \out, ~sun.reverbBus,
                \freq, freq,
                \amp, amp,
                \attack, attack,
                \release, release,
                \cutoff, note.linexp(24, ~sun.lowHighSplit - 1, 250, 1100).clip(250, 1100)
            ], ~sun.sourceGroup);
        } {
            amp = ~sun.velocityToAmpHigh.(vel);

            // High notes use zero attack and shorter release
            attack = 0.0;
            release = note.linlin(~sun.lowHighSplit, 108, 0.35, 0.12).clip(0.12, 0.35);

            synth = Synth(\sunHighVoice, [
                \out, ~sun.reverbBus,
                \freq, freq,
                \amp, amp,
                \attack, attack,
                \release, release,
                \hpf, note.linexp(~sun.lowHighSplit, 108, 900, 4000).clip(900, 4000)
            ], ~sun.sourceGroup);
        };

        ~sun.activeNotes[note] = synth;

        (
            "NOTE ON | note: " ++ note
            ++ " freq: " ++ freq.round(0.1)
            ++ " vel: " ++ vel
            ++ " amp: " ++ amp.round(0.001)
        ).postln;
    });

    // --------------------------------------------------------
    // Note off
    // --------------------------------------------------------

    MIDIdef.noteOff(\sunLiveSplitNoteOff, { |vel, note, chan, src|
        var synth;

        synth = ~sun.activeNotes[note];
        if(synth.notNil) {
            synth.set(\gate, 0);
            ~sun.activeNotes.removeAt(note);
        };

        ("NOTE OFF | note: " ++ note).postln;
    });

    // --------------------------------------------------------
    // Optional CC controls
    // You can adjust these later based on your MiniLab 3 mapping
    // --------------------------------------------------------

    MIDIdef.cc(\sunReverbMixCC, { |val|
        var mix;
        mix = val.linlin(0, 127, 0.0, 0.65);
        ~sun.reverbSynth.set(\mix, mix);
        ("Reverb mix: " ++ mix.round(0.01)).postln;
    }, 25);

    MIDIdef.cc(\sunReverbRoomCC, { |val|
        var room;
        room = val.linlin(0, 127, 0.2, 1.0);
        ~sun.reverbSynth.set(\room, room);
        ("Reverb room: " ++ room.round(0.01)).postln;
    }, 26);

    MIDIdef.cc(\sunReverbDampCC, { |val|
        var damp;
        damp = val.linlin(0, 127, 0.1, 0.9);
        ~sun.reverbSynth.set(\damp, damp);
        ("Reverb damp: " ++ damp.round(0.01)).postln;
    }, 27);

    "Sun live split performance mode is ready.".postln;
    "Low notes -> organ/orchestral bass style.".postln;
    "High notes -> fast bright voice with zero attack.".postln;
    "Velocity controls amplitude.".postln;
    "Play chords directly on the MiniLab 3.".postln;
};
)