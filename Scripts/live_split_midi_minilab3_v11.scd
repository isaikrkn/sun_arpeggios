(
s.waitForBoot {

    // --------------------------------------------------------
    // Global state
    // --------------------------------------------------------

    ~sun = IdentityDictionary.new;

    ~sun[\activeNotes] = IdentityDictionary.new;
    ~sun[\heldLow] = IdentitySet.new;
    ~sun[\heldHigh] = IdentitySet.new;
    ~sun[\lowVelocities] = IdentityDictionary.new;
    ~sun[\highVelocities] = IdentityDictionary.new;

    ~sun[\lowHighSplit] = 60;
    ~sun[\highNoteCeiling] = 96;
    ~sun[\arpRoutine] = nil;
    ~sun[\arpRate] = 0.095367432;
    ~sun[\arpEnabled] = true;

    // Global dynamic controls
    ~sun[\dynamicScale] = 1.0;
    ~sun[\lowDynamicScale] = 1.0;
    ~sun[\highDynamicScale] = 1.0;

    // Performance controls
    ~sun[\highFadeOut] = 3.0;
    ~sun[\highBrightnessScale] = 1.0;
    ~sun[\extraVoiceProb] = 0.18;
    ~sun[\velocitySensitivity] = 1.0;

    ~sun[\reverbBus] = Bus.audio(s, 2);
    ~sun[\sourceGroup] = Group.head(s);
    ~sun[\fxGroup] = Group.after(~sun[\sourceGroup]);

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
    // Dry attack, automatic free
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

    ~sun[\reverbSynth] = Synth.tail(~sun[\fxGroup], \sunMasterReverb, [
        \inBus, ~sun[\reverbBus],
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
    // Reset helper
    // --------------------------------------------------------

    ~sun[\resetControls] = { |state|
        state[\highNoteCeiling] = 96;
        state[\arpRate] = 0.095367432;
        state[\dynamicScale] = 1.0;
        state[\lowDynamicScale] = 1.0;
        state[\highDynamicScale] = 1.0;
        state[\highFadeOut] = 3.0;
        state[\highBrightnessScale] = 1.0;
        state[\extraVoiceProb] = 0.18;
        state[\lowHighSplit] = 60;
        state[\arpEnabled] = true;
        state[\velocitySensitivity] = 1.0;
        "Performance controls reset.".postln;
    };

    // --------------------------------------------------------
    // Arpeggiator start
    // --------------------------------------------------------

    ~sun[\startArp] = { |state|
        if(state[\arpEnabled] and: { state[\arpRoutine].isNil }) {
            state[\arpRoutine] = Routine({
                var notes, baseNote, octaveShift, midiNote, vel;
                var amp, hpf, lpf, bright, fadeOut, extraVoice;
                var ceilingRef, velScale;

                loop {
                    notes = state[\heldHigh].asArray.sort;

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

                        midiNote = (baseNote + octaveShift).min(state[\highNoteCeiling]);
                        vel = state[\highVelocities].at(baseNote);
                        if(vel.isNil) { vel = 100 };

                        ceilingRef = state[\highNoteCeiling].max(state[\lowHighSplit] + 1);

                        // Velocity curve for high register dynamics
                        velScale = vel.linlin(1, 127, 0.55, 1.35);
                        velScale = velScale * state[\velocitySensitivity];
                        velScale = velScale.max(0.4).min(1.6);

                        // Softer touch -> quieter and darker
                        // Harder touch -> louder and brighter
                        amp = vel.linexp(1, 127, 0.010, 0.085);
                        amp = amp * midiNote.linlin(state[\lowHighSplit], ceilingRef, 1.0, 0.45);
                        amp = amp * state[\highDynamicScale] * state[\dynamicScale];
                        amp = amp.max(0.008).min(0.11);

                        hpf = midiNote.linexp(state[\lowHighSplit], ceilingRef, 850, 3000);
                        hpf = hpf.max(850).min(3000);

                        lpf = midiNote.linexp(state[\lowHighSplit], ceilingRef, 7600, 3800);
                        lpf = lpf * vel.linexp(1, 127, 0.85, 1.20);
                        lpf = lpf.max(3500).min(9000);

                        bright = midiNote.linlin(state[\lowHighSplit], ceilingRef, 0.9, 0.15);
                        bright = bright * vel.linlin(1, 127, 0.7, 1.45);
                        bright = bright * state[\highBrightnessScale];
                        bright = bright.max(0.05).min(1.8);

                        fadeOut = vel.linlin(1, 127, state[\highFadeOut] * 1.15, state[\highFadeOut] * 0.75);
                        fadeOut = fadeOut.max(0.6).min(5.0);

                        Synth(\sunHighArpVoice, [
                            \out, state[\reverbBus],
                            \freq, midiNote.midicps,
                            \amp, amp,
                            \attack, 0.0001,
                            \fadeOut, fadeOut,
                            \hpf, hpf,
                            \lpf, lpf,
                            \bright, bright
                        ], state[\sourceGroup]);

                        extraVoice = state[\extraVoiceProb].coin and: { notes.size > 1 };

                        if(extraVoice) {
                            var ceilingRef2;

                            baseNote = notes.choose;

                            octaveShift =
                            if(baseNote >= 79) {
                                [0, 12].wchoose([0.7, 0.3]);
                            } {
                                [12, 24].wchoose([0.75, 0.25]);
                            };

                            midiNote = (baseNote + octaveShift).min(state[\highNoteCeiling]);
                            ceilingRef2 = state[\highNoteCeiling].max(state[\lowHighSplit] + 1);

                            amp = vel.linexp(1, 127, 0.008, 0.045);
                            amp = amp * midiNote.linlin(state[\lowHighSplit], ceilingRef2, 1.0, 0.50);
                            amp = amp * state[\highDynamicScale] * state[\dynamicScale];
                            amp = amp.max(0.006).min(0.05);

                            hpf = midiNote.linexp(state[\lowHighSplit], ceilingRef2, 1000, 3200);
                            hpf = hpf.max(1000).min(3200);

                            lpf = midiNote.linexp(state[\lowHighSplit], ceilingRef2, 7000, 3600);
                            lpf = lpf * vel.linexp(1, 127, 0.85, 1.15);
                            lpf = lpf.max(3200).min(8000);

                            bright = midiNote.linlin(state[\lowHighSplit], ceilingRef2, 0.7, 0.08);
                            bright = bright * vel.linlin(1, 127, 0.7, 1.3);
                            bright = bright * state[\highBrightnessScale];
                            bright = bright.max(0.05).min(1.4);

                            Synth(\sunHighArpVoice, [
                                \out, state[\reverbBus],
                                \freq, midiNote.midicps,
                                \amp, amp,
                                \attack, 0.0001,
                                \fadeOut, (fadeOut * 0.75).max(0.4),
                                \hpf, hpf,
                                \lpf, lpf,
                                \bright, bright
                            ], state[\sourceGroup]);
                        };
                    };

                    state[\arpRate].wait;
                }
            }).play(SystemClock);
        };
    };

    // --------------------------------------------------------
    // Arpeggiator stop
    // --------------------------------------------------------

    ~sun[\stopArp] = { |state|
        if(state[\heldHigh].isEmpty) {
            if(state[\arpRoutine].notNil) {
                state[\arpRoutine].stop;
                state[\arpRoutine] = nil;
            };
        };
    };

    // --------------------------------------------------------
    // MIDI note handling
    // --------------------------------------------------------

    MIDIdef.noteOn(\sunLiveSplitNoteOn, { |vel, note, chan, src|
        var freq, synth, amp, attack, release, cutoff;
        var velScale, noteCutoffBase;

        if(note < ~sun[\lowHighSplit]) {
            ~sun[\heldLow].add(note);
            ~sun[\lowVelocities].put(note, vel);

            if(~sun[\activeNotes].at(note).notNil) {
                ~sun[\activeNotes].at(note).set(\gate, 0);
                ~sun[\activeNotes].removeAt(note);
            };

            freq = note.midicps;

            // Velocity curve for low register dynamics
            velScale = vel.linlin(1, 127, 0.55, 1.35);
            velScale = velScale * ~sun[\velocitySensitivity];
            velScale = velScale.max(0.4).min(1.6);

            // Piano -> softer and darker
            // Forte -> louder and brighter
            amp = vel.linexp(1, 127, 0.025, 0.22);
            amp = amp * ~sun[\lowDynamicScale] * ~sun[\dynamicScale];
            amp = amp.max(0.015).min(0.30);

            // Softer touch gives slower attack, harder touch gives firmer attack
            attack = vel.linlin(1, 127, 0.18, 0.05);
            attack = attack * note.linlin(24, (~sun[\lowHighSplit] - 1).max(25), 1.1, 0.9);
            attack = attack.max(0.04).min(0.22);

            // Softer touch lets the note bloom longer, harder touch is tighter
            release = vel.linlin(1, 127, 3.2, 1.6);
            release = release.max(1.2).min(3.5);

            // Base cutoff from note position, then shaped by velocity
            noteCutoffBase = note.linexp(24, (~sun[\lowHighSplit] - 1).max(25), 220, 900);
            cutoff = noteCutoffBase * velScale;
            cutoff = cutoff.max(220).min(1500);

            synth = Synth(\sunLowVoice, [
                \out, ~sun[\reverbBus],
                \freq, freq,
                \amp, amp,
                \attack, attack,
                \release, release,
                \cutoff, cutoff
            ], ~sun[\sourceGroup]);

            ~sun[\activeNotes].put(note, synth);
        } {
            ~sun[\heldHigh].add(note);
            ~sun[\highVelocities].put(note, vel);
            if(~sun[\arpEnabled]) {
                ~sun[\startArp].value(~sun);
            };
        };

        ("NOTE ON | " ++ note ++ " vel: " ++ vel).postln;
    });

    MIDIdef.noteOff(\sunLiveSplitNoteOff, { |vel, note, chan, src|
        var synth;

        ~sun[\heldLow].remove(note);
        ~sun[\heldHigh].remove(note);
        ~sun[\lowVelocities].removeAt(note);
        ~sun[\highVelocities].removeAt(note);

        synth = ~sun[\activeNotes].at(note);
        if(synth.notNil) {
            synth.set(\gate, 0);
            ~sun[\activeNotes].removeAt(note);
        };

        ~sun[\stopArp].value(~sun);

        ("NOTE OFF | " ++ note).postln;
    });

    // --------------------------------------------------------
    // MIDI performance mapping
    // Adjust CC and pad note numbers if needed
    // --------------------------------------------------------

    // CC 21 -> high note ceiling
    MIDIdef.cc(\sunHighCeilingCC, { |val|
        ~sun[\highNoteCeiling] = val.linlin(0, 127, 84, 108).round(1).asInteger;
        ("High note ceiling: " ++ ~sun[\highNoteCeiling]).postln;
    }, 21);

    // CC 22 -> arp rate
    MIDIdef.cc(\sunArpRateCC, { |val|
        ~sun[\arpRate] = val.linlin(0, 127, 0.05, 0.22);
        ("Arp rate: " ++ ~sun[\arpRate].round(0.001)).postln;
    }, 22);

    // CC 23 -> global dynamics
    MIDIdef.cc(\sunDynamicScaleCC, { |val|
        ~sun[\dynamicScale] = val.linlin(0, 127, 0.4, 1.7);
        ("Dynamic scale: " ++ ~sun[\dynamicScale].round(0.01)).postln;
    }, 23);

    // CC 24 -> low dynamics
    MIDIdef.cc(\sunLowDynamicCC, { |val|
        ~sun[\lowDynamicScale] = val.linlin(0, 127, 0.5, 1.6);
        ("Low dynamic scale: " ++ ~sun[\lowDynamicScale].round(0.01)).postln;
    }, 24);

    // CC 25 -> reverb mix
    MIDIdef.cc(\sunReverbMixCC, { |val|
        var mix;
        mix = val.linlin(0, 127, 0.0, 0.55);
        ~sun[\reverbSynth].set(\mix, mix);
        ("Reverb mix: " ++ mix.round(0.01)).postln;
    }, 25);

    // CC 26 -> reverb room
    MIDIdef.cc(\sunReverbRoomCC, { |val|
        var room;
        room = val.linlin(0, 127, 0.2, 1.0);
        ~sun[\reverbSynth].set(\room, room);
        ("Reverb room: " ++ room.round(0.01)).postln;
    }, 26);

    // CC 27 -> reverb damp
    MIDIdef.cc(\sunReverbDampCC, { |val|
        var damp;
        damp = val.linlin(0, 127, 0.15, 0.85);
        ~sun[\reverbSynth].set(\damp, damp);
        ("Reverb damp: " ++ damp.round(0.01)).postln;
    }, 27);

    // CC 28 -> high dynamics
    MIDIdef.cc(\sunHighDynamicCC, { |val|
        ~sun[\highDynamicScale] = val.linlin(0, 127, 0.4, 1.5);
        ("High dynamic scale: " ++ ~sun[\highDynamicScale].round(0.01)).postln;
    }, 28);

    // CC 29 -> high fade out
    MIDIdef.cc(\sunHighFadeOutCC, { |val|
        ~sun[\highFadeOut] = val.linlin(0, 127, 0.6, 4.5);
        ("High fade out: " ++ ~sun[\highFadeOut].round(0.01)).postln;
    }, 29);

    // CC 30 -> split point
    MIDIdef.cc(\sunSplitPointCC, { |val|
        ~sun[\lowHighSplit] = val.linlin(0, 127, 48, 72).round(1).asInteger;
        ("Split point: " ++ ~sun[\lowHighSplit]).postln;
    }, 30);

    // CC 31 -> high brightness
    MIDIdef.cc(\sunHighBrightnessCC, { |val|
        ~sun[\highBrightnessScale] = val.linlin(0, 127, 0.3, 1.6);
        ("High brightness scale: " ++ ~sun[\highBrightnessScale].round(0.01)).postln;
    }, 31);

    // CC 32 -> extra voice probability
    MIDIdef.cc(\sunExtraVoiceProbCC, { |val|
        ~sun[\extraVoiceProb] = val.linlin(0, 127, 0.0, 0.40);
        ("Extra voice probability: " ++ ~sun[\extraVoiceProb].round(0.01)).postln;
    }, 32);

    // CC 33 -> velocity sensitivity
    MIDIdef.cc(\sunVelocitySensitivityCC, { |val|
        ~sun[\velocitySensitivity] = val.linlin(0, 127, 0.5, 1.6);
        ("Velocity sensitivity: " ++ ~sun[\velocitySensitivity].round(0.01)).postln;
    }, 33);

    // Pads -> dynamic presets and utility
    MIDIdef.noteOn(\sunDynamicPads, { |vel, note|
        if(vel > 0) {
            case
            { note == 36 } {
                ~sun[\dynamicScale] = 0.45;
                "Dynamic preset: pp".postln;
            }
            { note == 37 } {
                ~sun[\dynamicScale] = 0.65;
                "Dynamic preset: p".postln;
            }
            { note == 38 } {
                ~sun[\dynamicScale] = 0.85;
                "Dynamic preset: mp".postln;
            }
            { note == 39 } {
                ~sun[\dynamicScale] = 1.0;
                "Dynamic preset: mf".postln;
            }
            { note == 40 } {
                ~sun[\dynamicScale] = 1.25;
                "Dynamic preset: f".postln;
            }
            { note == 41 } {
                ~sun[\dynamicScale] = 1.5;
                "Dynamic preset: ff".postln;
            }
            { note == 42 } {
                ~sun[\arpEnabled] = ~sun[\arpEnabled].not;
                if(~sun[\arpEnabled].not) {
                    if(~sun[\arpRoutine].notNil) {
                        ~sun[\arpRoutine].stop;
                        ~sun[\arpRoutine] = nil;
                    };
                } {
                    if(~sun[\heldHigh].notEmpty) {
                        ~sun[\startArp].value(~sun);
                    };
                };
                ("Arp enabled: " ++ ~sun[\arpEnabled]).postln;
            }
            { note == 43 } {
                ~sun[\resetControls].value(~sun);
            }
            { note == 44 } {
                ~sun[\velocitySensitivity] = 0.7;
                "Velocity mode: gentle".postln;
            }
            { note == 45 } {
                ~sun[\velocitySensitivity] = 1.0;
                "Velocity mode: normal".postln;
            }
            { note == 46 } {
                ~sun[\velocitySensitivity] = 1.35;
                "Velocity mode: expressive".postln;
            };
        };
    });

    "Velocity-responsive split arp mode ready.".postln;
    "Soft touch = more piano.".postln;
    "Hard touch = more forte.".postln;
    "CC 21 = high note ceiling".postln;
    "CC 22 = arp rate".postln;
    "CC 23 = global dynamics".postln;
    "CC 24 = low dynamics".postln;
    "CC 25 = reverb mix".postln;
    "CC 26 = reverb room".postln;
    "CC 27 = reverb damp".postln;
    "CC 28 = high dynamics".postln;
    "CC 29 = high fade out".postln;
    "CC 30 = split point".postln;
    "CC 31 = high brightness".postln;
    "CC 32 = extra voice probability".postln;
    "CC 33 = velocity sensitivity".postln;
    "Pads 36-41 = pp / p / mp / mf / f / ff".postln;
    "Pad 42 = arp on/off".postln;
    "Pad 43 = reset controls".postln;
    "Pads 44-46 = gentle / normal / expressive velocity response".postln;
};
)


(
MIDIdef.freeAll;

if(~sun.notNil) {
    if(~sun[\arpRoutine].notNil) {
        ~sun[\arpRoutine].stop;
        ~sun[\arpRoutine] = nil;
    };

    if(~sun[\activeNotes].notNil) {
        ~sun[\activeNotes].keysValuesDo { |note, synth|
            if(synth.notNil) { synth.set(\gate, 0) };
        };
    };

    if(~sun[\reverbSynth].notNil) { ~sun[\reverbSynth].free };
    if(~sun[\reverbBus].notNil) { ~sun[\reverbBus].free };
    if(~sun[\sourceGroup].notNil) { ~sun[\sourceGroup].free };
    if(~sun[\fxGroup].notNil) { ~sun[\fxGroup].free };

    ~sun = nil;
};

"Cleaned previous state.".postln;
)