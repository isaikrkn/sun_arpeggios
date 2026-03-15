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

    ~sun[\dynamicScale] = 1.0;
    ~sun[\lowDynamicScale] = 1.0;
    ~sun[\highDynamicScale] = 1.0;

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
    // High register one-shot arp voice
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
        state[\reverbSynth].set(\mix, 0.24, \room, 0.82, \damp, 0.52);
        "Performance controls reset.".postln;
    };

    // --------------------------------------------------------
    // Scene system
    // --------------------------------------------------------

    ~sun[\applyScene] = { |state, sceneName|
        switch(sceneName,

            \darkAmbient, {
                state[\highNoteCeiling] = 90;
                state[\arpRate] = 0.135;
                state[\dynamicScale] = 0.75;
                state[\lowDynamicScale] = 1.10;
                state[\highDynamicScale] = 0.72;
                state[\highFadeOut] = 4.2;
                state[\highBrightnessScale] = 0.45;
                state[\extraVoiceProb] = 0.08;
                state[\lowHighSplit] = 58;
                state[\velocitySensitivity] = 0.9;

                state[\reverbSynth].set(
                    \mix, 0.38,
                    \room, 0.92,
                    \damp, 0.62
                );

                "Scene loaded: darkAmbient".postln;
            },

            \organHall, {
                state[\highNoteCeiling] = 92;
                state[\arpRate] = 0.11;
                state[\dynamicScale] = 0.95;
                state[\lowDynamicScale] = 1.25;
                state[\highDynamicScale] = 0.80;
                state[\highFadeOut] = 3.8;
                state[\highBrightnessScale] = 0.55;
                state[\extraVoiceProb] = 0.10;
                state[\lowHighSplit] = 60;
                state[\velocitySensitivity] = 0.95;

                state[\reverbSynth].set(
                    \mix, 0.34,
                    \room, 0.95,
                    \damp, 0.50
                );

                "Scene loaded: organHall".postln;
            },

            \brightGlass, {
                state[\highNoteCeiling] = 102;
                state[\arpRate] = 0.07;
                state[\dynamicScale] = 1.00;
                state[\lowDynamicScale] = 0.82;
                state[\highDynamicScale] = 1.18;
                state[\highFadeOut] = 2.0;
                state[\highBrightnessScale] = 1.45;
                state[\extraVoiceProb] = 0.22;
                state[\lowHighSplit] = 62;
                state[\velocitySensitivity] = 1.1;

                state[\reverbSynth].set(
                    \mix, 0.20,
                    \room, 0.72,
                    \damp, 0.35
                );

                "Scene loaded: brightGlass".postln;
            },

            \cinematicForte, {
                state[\highNoteCeiling] = 100;
                state[\arpRate] = 0.085;
                state[\dynamicScale] = 1.35;
                state[\lowDynamicScale] = 1.22;
                state[\highDynamicScale] = 1.12;
                state[\highFadeOut] = 3.4;
                state[\highBrightnessScale] = 0.95;
                state[\extraVoiceProb] = 0.24;
                state[\lowHighSplit] = 59;
                state[\velocitySensitivity] = 1.2;

                state[\reverbSynth].set(
                    \mix, 0.30,
                    \room, 0.88,
                    \damp, 0.46
                );

                "Scene loaded: cinematicForte".postln;
            }
        );
    };

    // --------------------------------------------------------
    // Arpeggiator start
    // --------------------------------------------------------

    ~sun[\startArp] = { |state|
        if(state[\arpEnabled] and: { state[\arpRoutine].isNil }) {
            state[\arpRoutine] = Routine({
                var notes, baseNote, octaveShift, midiNote, vel;
                var amp, hpf, lpf, bright, fadeOut, extraVoice;
                var ceilingRef, velScale, ceilingRange;

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
                        ceilingRange = ceilingRef;

                        velScale = vel.linlin(1, 127, 0.55, 1.35);
                        velScale = velScale * state[\velocitySensitivity];
                        velScale = velScale.max(0.4).min(1.6);

                        amp = vel.linexp(1, 127, 0.010, 0.085);
                        amp = amp * midiNote.linlin(state[\lowHighSplit], ceilingRange, 1.0, 0.45);
                        amp = amp * state[\highDynamicScale] * state[\dynamicScale];
                        amp = amp.max(0.008).min(0.11);

                        hpf = midiNote.linexp(state[\lowHighSplit], ceilingRange, 850, 3000);
                        hpf = hpf.max(850).min(3000);

                        lpf = midiNote.linexp(state[\lowHighSplit], ceilingRange, 7600, 3800);
                        lpf = lpf * vel.linexp(1, 127, 0.85, 1.20);
                        lpf = lpf.max(3500).min(9000);

                        bright = midiNote.linlin(state[\lowHighSplit], ceilingRange, 0.9, 0.15);
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
        var velScale, noteCutoffBase, splitTop;

        splitTop = (~sun[\lowHighSplit] - 1).max(25);

        if(note < ~sun[\lowHighSplit]) {
            ~sun[\heldLow].add(note);
            ~sun[\lowVelocities].put(note, vel);

            if(~sun[\activeNotes].at(note).notNil) {
                ~sun[\activeNotes].at(note).set(\gate, 0);
                ~sun[\activeNotes].removeAt(note);
            };

            freq = note.midicps;

            velScale = vel.linlin(1, 127, 0.55, 1.35);
            velScale = velScale * ~sun[\velocitySensitivity];
            velScale = velScale.max(0.4).min(1.6);

            amp = vel.linexp(1, 127, 0.025, 0.22);
            amp = amp * ~sun[\lowDynamicScale] * ~sun[\dynamicScale];
            amp = amp.max(0.015).min(0.30);

            attack = vel.linlin(1, 127, 0.18, 0.05);
            attack = attack * note.linlin(24, splitTop, 1.1, 0.9);
            attack = attack.max(0.04).min(0.22);

            release = vel.linlin(1, 127, 3.2, 1.6);
            release = release.max(1.2).min(3.5);

            noteCutoffBase = note.linexp(24, splitTop, 220, 900);
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
    // MIDI CC mapping
    // --------------------------------------------------------

    MIDIdef.cc(\sunHighCeilingCC, { |val|
        ~sun[\highNoteCeiling] = val.linlin(0, 127, 84, 108).round(1).asInteger;
        ("High note ceiling: " ++ ~sun[\highNoteCeiling]).postln;
    }, 21);

    MIDIdef.cc(\sunArpRateCC, { |val|
        ~sun[\arpRate] = val.linlin(0, 127, 0.05, 0.22);
        ("Arp rate: " ++ ~sun[\arpRate].round(0.001)).postln;
    }, 22);

    MIDIdef.cc(\sunDynamicScaleCC, { |val|
        ~sun[\dynamicScale] = val.linlin(0, 127, 0.4, 1.7);
        ("Dynamic scale: " ++ ~sun[\dynamicScale].round(0.01)).postln;
    }, 23);

    MIDIdef.cc(\sunLowDynamicCC, { |val|
        ~sun[\lowDynamicScale] = val.linlin(0, 127, 0.5, 1.6);
        ("Low dynamic scale: " ++ ~sun[\lowDynamicScale].round(0.01)).postln;
    }, 24);

    MIDIdef.cc(\sunReverbMixCC, { |val|
        var mix;
        mix = val.linlin(0, 127, 0.0, 0.55);
        ~sun[\reverbSynth].set(\mix, mix);
        ("Reverb mix: " ++ mix.round(0.01)).postln;
    }, 25);

    MIDIdef.cc(\sunReverbRoomCC, { |val|
        var room;
        room = val.linlin(0, 127, 0.2, 1.0);
        ~sun[\reverbSynth].set(\room, room);
        ("Reverb room: " ++ room.round(0.01)).postln;
    }, 26);

    MIDIdef.cc(\sunReverbDampCC, { |val|
        var damp;
        damp = val.linlin(0, 127, 0.15, 0.85);
        ~sun[\reverbSynth].set(\damp, damp);
        ("Reverb damp: " ++ damp.round(0.01)).postln;
    }, 27);

    MIDIdef.cc(\sunHighDynamicCC, { |val|
        ~sun[\highDynamicScale] = val.linlin(0, 127, 0.4, 1.5);
        ("High dynamic scale: " ++ ~sun[\highDynamicScale].round(0.01)).postln;
    }, 28);

    MIDIdef.cc(\sunHighFadeOutCC, { |val|
        ~sun[\highFadeOut] = val.linlin(0, 127, 0.6, 4.5);
        ("High fade out: " ++ ~sun[\highFadeOut].round(0.01)).postln;
    }, 29);

    MIDIdef.cc(\sunSplitPointCC, { |val|
        ~sun[\lowHighSplit] = val.linlin(0, 127, 48, 72).round(1).asInteger;
        ("Split point: " ++ ~sun[\lowHighSplit]).postln;
    }, 30);

    MIDIdef.cc(\sunHighBrightnessCC, { |val|
        ~sun[\highBrightnessScale] = val.linlin(0, 127, 0.3, 1.6);
        ("High brightness scale: " ++ ~sun[\highBrightnessScale].round(0.01)).postln;
    }, 31);

    MIDIdef.cc(\sunExtraVoiceProbCC, { |val|
        ~sun[\extraVoiceProb] = val.linlin(0, 127, 0.0, 0.40);
        ("Extra voice probability: " ++ ~sun[\extraVoiceProb].round(0.01)).postln;
    }, 32);

    MIDIdef.cc(\sunVelocitySensitivityCC, { |val|
        ~sun[\velocitySensitivity] = val.linlin(0, 127, 0.5, 1.6);
        ("Velocity sensitivity: " ++ ~sun[\velocitySensitivity].round(0.01)).postln;
    }, 33);

    // --------------------------------------------------------
    // Pads: scenes, dynamics, utility
    // --------------------------------------------------------

    MIDIdef.noteOn(\sunPadsScenesAndDynamics, { |vel, note|
        if(vel > 0) {
            case
            { note == 36 } {
                ~sun[\applyScene].value(~sun, \darkAmbient);
            }
            { note == 37 } {
                ~sun[\applyScene].value(~sun, \organHall);
            }
            { note == 38 } {
                ~sun[\applyScene].value(~sun, \brightGlass);
            }
            { note == 39 } {
                ~sun[\applyScene].value(~sun, \cinematicForte);
            }
            { note == 40 } {
                ~sun[\dynamicScale] = 0.50;
                "Dynamic preset: pp".postln;
            }
            { note == 41 } {
                ~sun[\dynamicScale] = 1.00;
                "Dynamic preset: mf".postln;
            }
            { note == 42 } {
                ~sun[\dynamicScale] = 1.45;
                "Dynamic preset: ff".postln;
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
            }
            { note == 47 } {
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
            };
        };
    });

    "Complete scene-based split arp system ready.".postln;
    "Scenes: 36 darkAmbient, 37 organHall, 38 brightGlass, 39 cinematicForte".postln;
    "Dynamics: 40 pp, 41 mf, 42 ff".postln;
    "Reset: 43".postln;
    "Velocity modes: 44 gentle, 45 normal, 46 expressive".postln;
    "Arp toggle: 47".postln;
    "CC 21 ceiling, 22 arpRate, 23 globalDyn, 24 lowDyn, 25 mix, 26 room, 27 damp".postln;
    "CC 28 highDyn, 29 fadeOut, 30 split, 31 brightness, 32 extraVoiceProb, 33 velocitySensitivity".postln;
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
            if(synth.notNil) {
                synth.set(\gate, 0);
            };
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