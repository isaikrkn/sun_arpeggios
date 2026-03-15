(
s.waitForBoot {

    // --------------------------------------------------------
    // Global state
    // --------------------------------------------------------

    ~sun = ();
    ~sun.activeNotes = IdentityDictionary.new;
    ~sun.heldNotes = IdentitySet.new;
    ~sun.lowVelocities = IdentityDictionary.new;
    ~sun.highVelocities = IdentityDictionary.new;

    ~sun.lowHighSplit = 60;
    ~sun.highNoteCeiling = 96;
    ~sun.arpRoutine = nil;
    ~sun.arpRate = 0.095367432;

    // Global dynamic controls
    ~sun.dynamicScale = 1.0;
    ~sun.lowDynamicScale = 1.0;
    ~sun.highDynamicScale = 1.0;

	// New performance controls
	~sun.highFadeOut = 3.0;
	~sun.highBrightnessScale = 1.0;
	~sun.extraVoiceProb = 0.18;
	~sun.arpEnabled = true;

    ~sun.reverbBus = Bus.audio(s, 2);
    ~sun.sourceGroup = Group.head(s);
    ~sun.fxGroup = Group.after(~sun.sourceGroup);

    // --------------------------------------------------------
    // FX
    // --------------------------------------------------------

    SynthDef(\sunMasterReverb, {
        |inBus=0, out=0, mix=0.24, room=0.82, damp=0.52|
        var dry, wet, sig;

        dry = In.ar(inBus, 2);
        wet = FreeVerb.ar(dry, mix, room, damp);
        sig = XFade2.ar(dry, wet, mix.linlin(0, 1, -1, 1));
        sig = Limiter.ar(sig, 0.92);

        Out.ar(out, sig);
    }).add;

    // --------------------------------------------------------
    // Low register voice
    // Organ / contrabass inspired
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
    // High register one-shot voice
    // Dry attack, 3 second fade out, automatic free
    // --------------------------------------------------------

	SynthDef(\sunHighArpVoice, {
		|out=0, freq=440, amp=0.05, attack=0.0001, fadeOut=3.0, hpf=1400, lpf=7000, bright=0.6|
		var env, tone, air, sig, safeFreq;

		safeFreq = freq.clip(120, 5000);
		env = Env.perc(attack, fadeOut, 1, curve: -4).kr(doneAction: 2);

		tone = Mix([
			Pulse.ar(safeFreq, 0.45, 0.09),
			VarSaw.ar(safeFreq * 1.005, 0, 0.28, 0.05),
			SinOsc.ar(safeFreq * 2, 0, 0.035)
		]);

		air = Gendy1.ar(1, 1, 1, 1, safeFreq * 0.999, safeFreq * 1.001, 0.015, 0.01) * 0.02;

		sig = tone + air;
		sig = HPF.ar(sig, hpf);
		sig = LPF.ar(sig, lpf);
		sig = BPeakEQ.ar(sig, safeFreq.clip(500, 3500), 0.45, bright);
		sig = LeakDC.ar(sig);
		sig = tanh(sig * 0.85);
		sig = Splay.ar([sig, DelayC.ar(sig, 0.02, 0.0035)], 0.08);
		sig = Limiter.ar(sig, 0.8);

		Out.ar(out, sig * env * amp);
	}).add;

    s.sync;

    ~sun.reverbSynth = Synth.tail(~sun.fxGroup, \sunMasterReverb, [
        \inBus, ~sun.reverbBus,
        \out, 0,
        \mix, 0.24,
        \room, 0.82,
        \damp, 0.52
    ]);

    // --------------------------------------------------------
    // MIDI setup
    // --------------------------------------------------------

    MIDIClient.init;
    MIDIIn.connectAll;
    MIDIdef.freeAll;

    "Connected MIDI sources:".postln;
    MIDIClient.sources.do { |src, i|
        ("Source " ++ i ++ ": " ++ src.device ++ " | " ++ src.name).postln;
    };

    // --------------------------------------------------------
    // Arpeggiator start
    // --------------------------------------------------------

    ~sun.startArp = {
        if(~sun.arpRoutine.isNil) {
            ~sun.arpRoutine = Routine({
                var notes, baseNote, octaveShift, midiNote, vel, amp, hpf, lpf, bright, fadeOut, extraVoice;

                loop {
                    notes = ~sun.heldNotes.asArray.select { |n| n >= ~sun.lowHighSplit }.sort;

                    if(notes.notEmpty) {
                        baseNote = notes.choose;

                        octaveShift =
                        if(baseNote >= 84) {
                            [0, 12].wchoose([0.78, 0.22]);
                        } {
                            if(baseNote >= 72) {
                                [0, 12, 24].wchoose([0.46, 0.40, 0.14]);
                            } {
                                [0, 12, 24, 36].wchoose([0.34, 0.36, 0.23, 0.07]);
                            }
                        };

                        midiNote = (baseNote + octaveShift).min(~sun.highNoteCeiling);
                        vel = ~sun.highVelocities[baseNote] ? 100;

                        amp = midiNote.linlin(~sun.lowHighSplit, ~sun.highNoteCeiling, 0.07, 0.025);
                        amp = amp.max(0.02).min(0.07);
                        amp = amp * ~sun.highDynamicScale * ~sun.dynamicScale;
                        amp = amp.max(0.01).min(0.10);

                        hpf = midiNote.linexp(~sun.lowHighSplit, ~sun.highNoteCeiling, 900, 3200);
                        hpf = hpf.max(900).min(3200);

                        lpf = midiNote.linexp(~sun.lowHighSplit, ~sun.highNoteCeiling, 9000, 4200);
                        lpf = lpf.max(4200).min(9000);

                        bright = midiNote.linlin(~sun.lowHighSplit, ~sun.highNoteCeiling, 1.2, 0.2);
                        bright = bright.max(0.2).min(1.2);

                        fadeOut = 3.0;

                        Synth(\sunHighArpVoice, [
                            \out, ~sun.reverbBus,
                            \freq, midiNote.midicps,
                            \amp, amp,
                            \attack, 0.0001,
                            \fadeOut, fadeOut,
                            \hpf, hpf,
                            \lpf, lpf,
                            \bright, bright
                        ], ~sun.sourceGroup);

                        extraVoice = 0.18.coin and: { notes.size > 1 };

                        if(extraVoice) {
                            baseNote = notes.choose;

                            octaveShift =
                            if(baseNote >= 79) {
                                [0, 12].wchoose([0.7, 0.3]);
                            } {
                                [12, 24].wchoose([0.75, 0.25]);
                            };

                            midiNote = (baseNote + octaveShift).min(~sun.highNoteCeiling);

                            amp = midiNote.linlin(~sun.lowHighSplit, ~sun.highNoteCeiling, 0.035, 0.014);
                            amp = amp.max(0.014).min(0.035);
                            amp = amp * ~sun.highDynamicScale * ~sun.dynamicScale;
                            amp = amp.max(0.008).min(0.05);

                            hpf = midiNote.linexp(~sun.lowHighSplit, ~sun.highNoteCeiling, 1100, 3500);
                            hpf = hpf.max(1100).min(3500);

                            lpf = midiNote.linexp(~sun.lowHighSplit, ~sun.highNoteCeiling, 8000, 3800);
                            lpf = lpf.max(3800).min(8000);

                            bright = midiNote.linlin(~sun.lowHighSplit, ~sun.highNoteCeiling, 0.8, 0.1);
                            bright = bright.max(0.1).min(0.8);

                            Synth(\sunHighArpVoice, [
                                \out, ~sun.reverbBus,
                                \freq, midiNote.midicps,
                                \amp, amp,
                                \attack, 0.0001,
                                \fadeOut, 2.3,
                                \hpf, hpf,
                                \lpf, lpf,
                                \bright, bright
                            ], ~sun.sourceGroup);
                        };
                    };

                    ~sun.arpRate.wait;
                }
            }).play(SystemClock);
        };
    };

    // --------------------------------------------------------
    // Arpeggiator stop
    // --------------------------------------------------------

    ~sun.stopArp = {
        if(~sun.heldNotes.select({ |n| n >= ~sun.lowHighSplit }).isEmpty) {
            if(~sun.arpRoutine.notNil) {
                ~sun.arpRoutine.stop;
                ~sun.arpRoutine = nil;
            };
        };
    };

    // --------------------------------------------------------
    // MIDI note handling
    // --------------------------------------------------------

    MIDIdef.noteOn(\sunLiveSplitNoteOn, { |vel, note, chan, src|
        var freq, synth, amp, attack, release, cutoff;

        ~sun.heldNotes.add(note);

        if(note < ~sun.lowHighSplit) {
            ~sun.lowVelocities[note] = vel;

            if(~sun.activeNotes[note].notNil) {
                ~sun.activeNotes[note].set(\gate, 0);
                ~sun.activeNotes.removeAt(note);
            };

            freq = note.midicps;

            amp = vel.linlin(1, 127, 0.04, 0.22);
            amp = amp.max(0.04).min(0.22);
            amp = amp * ~sun.lowDynamicScale * ~sun.dynamicScale;
            amp = amp.max(0.02).min(0.28);

            attack = note.linlin(24, ~sun.lowHighSplit - 1, 0.14, 0.04);
            attack = attack.max(0.04).min(0.14);

            release = note.linlin(24, ~sun.lowHighSplit - 1, 2.8, 1.2);
            release = release.max(1.2).min(2.8);

            cutoff = note.linexp(24, ~sun.lowHighSplit - 1, 250, 1100);
            cutoff = cutoff.max(250).min(1100);

            synth = Synth(\sunLowVoice, [
                \out, ~sun.reverbBus,
                \freq, freq,
                \amp, amp,
                \attack, attack,
                \release, release,
                \cutoff, cutoff
            ], ~sun.sourceGroup);

            ~sun.activeNotes[note] = synth;
        } {
            ~sun.highVelocities[note] = vel;
            ~sun.startArp.value;
        };

        ("NOTE ON | " ++ note ++ " vel: " ++ vel).postln;
    });

    MIDIdef.noteOff(\sunLiveSplitNoteOff, { |vel, note, chan, src|
        var synth;

        ~sun.heldNotes.remove(note);
        ~sun.lowVelocities.removeAt(note);
        ~sun.highVelocities.removeAt(note);

        synth = ~sun.activeNotes[note];
        if(synth.notNil) {
            synth.set(\gate, 0);
            ~sun.activeNotes.removeAt(note);
        };

        ~sun.stopArp.value;

        ("NOTE OFF | " ++ note).postln;
    });

    // --------------------------------------------------------
    // MIDI CC controls
    // --------------------------------------------------------

    // CC 21 -> high note ceiling
    MIDIdef.cc(\sunHighCeilingCC, { |val|
        ~sun.highNoteCeiling = val.linlin(0, 127, 84, 108).round(1).asInteger;
        ("High note ceiling: " ++ ~sun.highNoteCeiling).postln;
    }, 21);

    // CC 22 -> arp rate
    MIDIdef.cc(\sunArpRateCC, { |val|
        ~sun.arpRate = val.linlin(0, 127, 0.05, 0.22);
        ("Arp rate: " ++ ~sun.arpRate.round(0.001)).postln;
    }, 22);

    // CC 23 -> global dynamic scale
    MIDIdef.cc(\sunDynamicScaleCC, { |val|
        ~sun.dynamicScale = val.linlin(0, 127, 0.4, 1.7);
        ("Dynamic scale: " ++ ~sun.dynamicScale.round(0.01)).postln;
    }, 23);

    // CC 24 -> low register dynamic scale
    MIDIdef.cc(\sunLowDynamicCC, { |val|
        ~sun.lowDynamicScale = val.linlin(0, 127, 0.5, 1.6);
        ("Low dynamic scale: " ++ ~sun.lowDynamicScale.round(0.01)).postln;
    }, 24);

    // CC 25 -> reverb mix
    MIDIdef.cc(\sunReverbMixCC, { |val|
        var mix;
        mix = val.linlin(0, 127, 0.0, 0.55);
        ~sun.reverbSynth.set(\mix, mix);
        ("Reverb mix: " ++ mix.round(0.01)).postln;
    }, 25);

    // CC 26 -> reverb room
    MIDIdef.cc(\sunReverbRoomCC, { |val|
        var room;
        room = val.linlin(0, 127, 0.2, 1.0);
        ~sun.reverbSynth.set(\room, room);
        ("Reverb room: " ++ room.round(0.01)).postln;
    }, 26);

    // CC 27 -> reverb damp
    MIDIdef.cc(\sunReverbDampCC, { |val|
        var damp;
        damp = val.linlin(0, 127, 0.15, 0.85);
        ~sun.reverbSynth.set(\damp, damp);
        ("Reverb damp: " ++ damp.round(0.01)).postln;
    }, 27);

    // CC 28 -> high register dynamic scale
    MIDIdef.cc(\sunHighDynamicCC, { |val|
        ~sun.highDynamicScale = val.linlin(0, 127, 0.4, 1.5);
        ("High dynamic scale: " ++ ~sun.highDynamicScale.round(0.01)).postln;
    }, 28);

    // --------------------------------------------------------
    // Dynamic presets on pads
    // Change pad note numbers if your MiniLab 3 sends different notes
    // --------------------------------------------------------

    MIDIdef.noteOn(\sunDynamicPads, { |vel, note|
        if(vel > 0) {
            case
            { note == 36 } {
                ~sun.dynamicScale = 0.45;
                "Dynamic preset: pp".postln;
            }
            { note == 37 } {
                ~sun.dynamicScale = 0.65;
                "Dynamic preset: p".postln;
            }
            { note == 38 } {
                ~sun.dynamicScale = 0.85;
                "Dynamic preset: mp".postln;
            }
            { note == 39 } {
                ~sun.dynamicScale = 1.0;
                "Dynamic preset: mf".postln;
            }
            { note == 40 } {
                ~sun.dynamicScale = 1.25;
                "Dynamic preset: f".postln;
            }
            { note == 41 } {
                ~sun.dynamicScale = 1.5;
                "Dynamic preset: ff".postln;
            };
        };
    });

    "Improved split arp mode ready.".postln;
    "CC 21 = high note ceiling".postln;
    "CC 22 = arp rate".postln;
    "CC 23 = global dynamics".postln;
    "CC 24 = low dynamics".postln;
    "CC 28 = high dynamics".postln;
    "Pads 36-41 = pp / p / mp / mf / f / ff".postln;
};
)