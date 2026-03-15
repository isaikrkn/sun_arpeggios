(
// ------------------------------------------------------------
// Sun Arpeggios GUI
// Simplified GUI with scene controls, parameter sliders,
// MIDI detection status, and basic signal monitoring.
// Comments are intentionally in English.
// ------------------------------------------------------------

GUI.qt;

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

    ~sun[\reverbMix] = 0.24;
    ~sun[\reverbRoom] = 0.82;
    ~sun[\reverbDamp] = 0.52;

    ~sun[\lastFreq] = 0.0;
    ~sun[\lastLevel] = 0.0;
    ~sun[\midiStatusText] = "No MIDI sources detected yet.";

    ~sun[\reverbBus] = Bus.audio(s, 2);
    ~sun[\sourceGroup] = Group.head(s);
    ~sun[\fxGroup] = Group.after(~sun[\sourceGroup]);

    ~sun[\window] = nil;
    ~sun[\monitorSynth] = nil;
    ~sun[\meterUpdater] = nil;
    ~sun[\midiNoteOnDef] = nil;
    ~sun[\midiNoteOffDef] = nil;
    ~sun[\oscLevelDef] = nil;

    // --------------------------------------------------------
    // SynthDefs
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

    SynthDef(\sunOutputMonitor, {
        |inBus=0|
        var sig, amp, trig;

        sig = In.ar(inBus, 2);
        amp = Amplitude.kr(Mix(sig), 0.03, 0.15);
        trig = Impulse.kr(15);

        SendReply.kr(trig, '/sunLevel', [amp]);
    }).add;

    s.sync;

    // --------------------------------------------------------
    // Audio graph
    // --------------------------------------------------------

    ~sun[\reverbSynth] = Synth.tail(~sun[\fxGroup], \sunMasterReverb, [
        \inBus, ~sun[\reverbBus],
        \out, 0,
        \mix, ~sun[\reverbMix],
        \room, ~sun[\reverbRoom],
        \damp, ~sun[\reverbDamp]
    ]);

    ~sun[\monitorSynth] = Synth.tail(~sun[\fxGroup], \sunOutputMonitor, [
        \inBus, 0
    ]);

    ~sun[\oscLevelDef] = OSCdef(\sunLevelWatcher, { |msg|
        if(msg.size > 3) {
            ~sun[\lastLevel] = msg[3].asFloat;
        };
    }, '/sunLevel');

    // --------------------------------------------------------
    // Helpers
    // --------------------------------------------------------

    ~sun[\updateReverb] = { |state|
        if(state[\reverbSynth].notNil) {
            state[\reverbSynth].set(
                \mix, state[\reverbMix],
                \room, state[\reverbRoom],
                \damp, state[\reverbDamp]
            );
        };
    };

    ~sun[\stopArp] = { |state|
        if(state[\heldHigh].isEmpty) {
            if(state[\arpRoutine].notNil) {
                state[\arpRoutine].stop;
                state[\arpRoutine] = nil;
            };
        };
    };

    ~sun[\startArp] = { |state|
        if(state[\arpEnabled] and: { state[\arpRoutine].isNil }) {
            state[\arpRoutine] = Routine({
                var notes, baseNote, octaveShift, midiNote, vel;
                var amp, hpf, lpf, bright, fadeOut, extraVoice;
                var ceilingRef;

                loop {
                    notes = state[\heldHigh].asArray.sort;

                    if(notes.notEmpty) {
                        baseNote = notes.choose;

                        octaveShift = if(baseNote >= 84) {
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

                        state[\lastFreq] = midiNote.midicps;

                        Synth(\sunHighArpVoice, [
                            \out, state[\reverbBus],
                            \freq, state[\lastFreq],
                            \amp, amp,
                            \attack, 0.0001,
                            \fadeOut, fadeOut,
                            \hpf, hpf,
                            \lpf, lpf,
                            \bright, bright
                        ], state[\sourceGroup]);

                        extraVoice = state[\extraVoiceProb].coin and: { notes.size > 1 };

                        if(extraVoice) {
                            baseNote = notes.choose;
                            octaveShift = if(baseNote >= 79) {
                                [0, 12].wchoose([0.7, 0.3]);
                            } {
                                [12, 24].wchoose([0.75, 0.25]);
                            };

                            midiNote = (baseNote + octaveShift).min(state[\highNoteCeiling]);

                            amp = vel.linexp(1, 127, 0.008, 0.045);
                            amp = amp * midiNote.linlin(state[\lowHighSplit], ceilingRef, 1.0, 0.50);
                            amp = amp * state[\highDynamicScale] * state[\dynamicScale];
                            amp = amp.max(0.006).min(0.05);

                            hpf = midiNote.linexp(state[\lowHighSplit], ceilingRef, 1000, 3200);
                            hpf = hpf.max(1000).min(3200);

                            lpf = midiNote.linexp(state[\lowHighSplit], ceilingRef, 7000, 3600);
                            lpf = lpf * vel.linexp(1, 127, 0.85, 1.15);
                            lpf = lpf.max(3200).min(8000);

                            bright = midiNote.linlin(state[\lowHighSplit], ceilingRef, 0.7, 0.08);
                            bright = bright * vel.linlin(1, 127, 0.7, 1.3);
                            bright = bright * state[\highBrightnessScale];
                            bright = bright.max(0.05).min(1.4);

                            state[\lastFreq] = midiNote.midicps;

                            Synth(\sunHighArpVoice, [
                                \out, state[\reverbBus],
                                \freq, state[\lastFreq],
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

    ~sun[\processNoteOn] = { |state, vel, note|
        var freq, synth, amp, attack, release, cutoff;
        var velScale, noteCutoffBase, splitTop;

        splitTop = (state[\lowHighSplit] - 1).max(25);

        if(note < state[\lowHighSplit]) {
            state[\heldLow].add(note);
            state[\lowVelocities].put(note, vel);

            if(state[\activeNotes].at(note).notNil) {
                state[\activeNotes].at(note).set(\gate, 0);
                state[\activeNotes].removeAt(note);
            };

            freq = note.midicps;
            state[\lastFreq] = freq;

            velScale = vel.linlin(1, 127, 0.55, 1.35);
            velScale = velScale * state[\velocitySensitivity];
            velScale = velScale.max(0.4).min(1.6);

            amp = vel.linexp(1, 127, 0.025, 0.22);
            amp = amp * state[\lowDynamicScale] * state[\dynamicScale];
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
                \out, state[\reverbBus],
                \freq, freq,
                \amp, amp,
                \attack, attack,
                \release, release,
                \cutoff, cutoff
            ], state[\sourceGroup]);

            state[\activeNotes].put(note, synth);
        } {
            state[\heldHigh].add(note);
            state[\highVelocities].put(note, vel);
            if(state[\arpEnabled]) {
                state[\startArp].value(state);
            };
        };
    };

    ~sun[\processNoteOff] = { |state, note|
        var synth;

        state[\heldLow].remove(note);
        state[\heldHigh].remove(note);
        state[\lowVelocities].removeAt(note);
        state[\highVelocities].removeAt(note);

        synth = state[\activeNotes].at(note);
        if(synth.notNil) {
            synth.set(\gate, 0);
            state[\activeNotes].removeAt(note);
        };

        state[\stopArp].value(state);
    };

    ~sun[\connectMidi] = { |state|
        if(state[\midiNoteOnDef].notNil) { state[\midiNoteOnDef].free };
        if(state[\midiNoteOffDef].notNil) { state[\midiNoteOffDef].free };

        state[\midiNoteOnDef] = MIDIFunc.noteOn({ |vel, note, chan, src|
            state[\processNoteOn].value(state, vel, note);
        });

        state[\midiNoteOffDef] = MIDIFunc.noteOff({ |vel, note, chan, src|
            state[\processNoteOff].value(state, note);
        });
    };

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
        state[\reverbMix] = 0.24;
        state[\reverbRoom] = 0.82;
        state[\reverbDamp] = 0.52;
        state[\updateReverb].value(state);
    };

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
                state[\reverbMix] = 0.38;
                state[\reverbRoom] = 0.92;
                state[\reverbDamp] = 0.62;
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
                state[\reverbMix] = 0.34;
                state[\reverbRoom] = 0.95;
                state[\reverbDamp] = 0.50;
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
                state[\reverbMix] = 0.20;
                state[\reverbRoom] = 0.72;
                state[\reverbDamp] = 0.35;
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
                state[\reverbMix] = 0.30;
                state[\reverbRoom] = 0.88;
                state[\reverbDamp] = 0.46;
            }
        );
        state[\updateReverb].value(state);
        if(state[\refreshGui].notNil) {
            state[\refreshGui].value;
        };
    };

    // --------------------------------------------------------
    // GUI
    // --------------------------------------------------------

    ~sun[\window] = Window("Sun Arpeggios GUI", Rect(80, 60, 960, 650)).front;
    ~sun[\window].background = Color(0.12, 0.12, 0.14);

    ~sun[\views] = IdentityDictionary.new;
    ~sun[\labels] = IdentityDictionary.new;

    StaticText(~sun[\window], Rect(20, 10, 500, 30))
        .string_("Sun Arpeggios — Performance GUI")
        .font_(Font("Arial", 18, true))
        .stringColor_(Color.white);

    StaticText(~sun[\window], Rect(20, 48, 180, 20))
        .string_("MIDI Detection Status")
        .stringColor_(Color.white);

    ~sun[\views][\midiStatus] = StaticText(~sun[\window], Rect(20, 72, 900, 44))
        .string_("Initializing MIDI...")
        .stringColor_(Color(0.82, 0.92, 1.0))
        .font_(Font("Arial", 11));

    Button(~sun[\window], Rect(20, 130, 120, 28))
        .states_([["Dark Ambient", Color.white, Color(0.25, 0.25, 0.40)]])
        .action_({ ~sun[\applyScene].value(~sun, \darkAmbient) });

    Button(~sun[\window], Rect(150, 130, 120, 28))
        .states_([["Organ Hall", Color.white, Color(0.25, 0.25, 0.40)]])
        .action_({ ~sun[\applyScene].value(~sun, \organHall) });

    Button(~sun[\window], Rect(280, 130, 120, 28))
        .states_([["Bright Glass", Color.white, Color(0.25, 0.25, 0.40)]])
        .action_({ ~sun[\applyScene].value(~sun, \brightGlass) });

    Button(~sun[\window], Rect(410, 130, 140, 28))
        .states_([["Cinematic Forte", Color.white, Color(0.25, 0.25, 0.40)]])
        .action_({ ~sun[\applyScene].value(~sun, \cinematicForte) });

    Button(~sun[\window], Rect(560, 130, 90, 28))
        .states_([["Reset", Color.white, Color(0.45, 0.25, 0.25)]])
        .action_({
            ~sun[\resetControls].value(~sun);
            ~sun[\refreshGui].value;
        });

    ~sun[\views][\arpButton] = Button(~sun[\window], Rect(660, 130, 120, 28))
        .states_([
            ["Arp ON", Color.white, Color(0.20, 0.45, 0.25)],
            ["Arp OFF", Color.white, Color(0.45, 0.20, 0.20)]
        ])
        .value_(0)
        .action_({ |btn|
            ~sun[\arpEnabled] = (btn.value == 0);
            if(~sun[\arpEnabled].not and: { ~sun[\arpRoutine].notNil }) {
                ~sun[\arpRoutine].stop;
                ~sun[\arpRoutine] = nil;
            };
            if(~sun[\arpEnabled] and: { ~sun[\heldHigh].notEmpty }) {
                ~sun[\startArp].value(~sun);
            };
        });

    Button(~sun[\window], Rect(790, 130, 110, 28))
        .states_([["Panic", Color.white, Color(0.55, 0.20, 0.20)]])
        .action_({
            if(~sun[\arpRoutine].notNil) {
                ~sun[\arpRoutine].stop;
                ~sun[\arpRoutine] = nil;
            };
            ~sun[\activeNotes].keysValuesDo { |note, synth|
                if(synth.notNil) { synth.set(\gate, 0) };
            };
            ~sun[\activeNotes].clear;
            ~sun[\heldLow].clear;
            ~sun[\heldHigh].clear;
            ~sun[\lowVelocities].clear;
            ~sun[\highVelocities].clear;
        });

    StaticText(~sun[\window], Rect(20, 175, 160, 20))
        .string_("Signal Monitor")
        .stringColor_(Color.white);

    StaticText(~sun[\window], Rect(20, 205, 70, 20))
        .string_("Level")
        .stringColor_(Color.white);

    ~sun[\views][\levelMeter] = LevelIndicator(~sun[\window], Rect(20, 230, 300, 18))
        .warning_(0.65)
        .critical_(0.85)
        .drawsPeak_(true)
        .numTicks_(12)
        .background_(Color(0.16, 0.16, 0.18))
        .value_(0);

    StaticText(~sun[\window], Rect(340, 205, 120, 20))
        .string_("Estimated Freq")
        .stringColor_(Color.white);

    ~sun[\views][\freqText] = StaticText(~sun[\window], Rect(340, 230, 160, 18))
        .string_("0.0 Hz")
        .stringColor_(Color(0.82, 0.92, 1.0));

    ~makeControl = { |key, label, lo, hi, x, y, isInt=false|
        var slider, valueLabel;

        StaticText(~sun[\window], Rect(x, y, 180, 20))
            .string_(label)
            .stringColor_(Color.white);

        valueLabel = StaticText(~sun[\window], Rect(x + 270, y, 80, 20))
            .stringColor_(Color(0.8, 0.9, 1.0))
            .align_(\right);

        slider = Slider(~sun[\window], Rect(x, y + 22, 350, 22))
            .background_(Color(0.18, 0.18, 0.20))
            .knobColor_(Color(0.30, 0.60, 0.95))
            .action_({ |sl|
                var mapped;
                mapped = sl.value.linlin(0, 1, lo, hi);
                if(isInt) { mapped = mapped.round(1).asInteger };
                ~sun[key] = mapped;
                if(key == \reverbMix or: { key == \reverbRoom } or: { key == \reverbDamp }) {
                    ~sun[\updateReverb].value(~sun);
                };
                valueLabel.string = if(isInt) { mapped.asString } { mapped.round(0.001).asString };
            });

        ~sun[\views][key] = slider;
        ~sun[\labels][key] = valueLabel;
    };

    ~makeControl.(\highNoteCeiling, "High Note Ceiling", 84, 108, 20, 280, true);
    ~makeControl.(\arpRate, "Arp Rate", 0.05, 0.22, 20, 340, false);
    ~makeControl.(\dynamicScale, "Global Dynamics", 0.4, 1.7, 20, 400, false);
    ~makeControl.(\lowDynamicScale, "Low Dynamics", 0.5, 1.6, 20, 460, false);
    ~makeControl.(\highDynamicScale, "High Dynamics", 0.4, 1.5, 20, 520, false);

    ~makeControl.(\highFadeOut, "High Fade Out", 0.6, 4.5, 500, 280, false);
    ~makeControl.(\lowHighSplit, "Split Point", 48, 72, 500, 340, true);
    ~makeControl.(\highBrightnessScale, "High Brightness", 0.3, 1.6, 500, 400, false);
    ~makeControl.(\extraVoiceProb, "Extra Voice Probability", 0.0, 0.40, 500, 460, false);
    ~makeControl.(\velocitySensitivity, "Velocity Sensitivity", 0.5, 1.6, 500, 520, false);
    ~makeControl.(\reverbMix, "Reverb Mix", 0.0, 0.55, 500, 580, false);

    StaticText(~sun[\window], Rect(20, 590, 420, 40))
        .string_("Velocity already controls piano/forte behavior. The GUI focuses on scenes, sound-shaping, MIDI status, and simple signal monitoring.")
        .stringColor_(Color(0.88, 0.93, 1.0));

    // --------------------------------------------------------
    // GUI refresh
    // --------------------------------------------------------

    ~sun[\refreshGui] = {
        var spec;

        spec = [
            [\highNoteCeiling, 84, 108, true],
            [\arpRate, 0.05, 0.22, false],
            [\dynamicScale, 0.4, 1.7, false],
            [\lowDynamicScale, 0.5, 1.6, false],
            [\highDynamicScale, 0.4, 1.5, false],
            [\highFadeOut, 0.6, 4.5, false],
            [\lowHighSplit, 48, 72, true],
            [\highBrightnessScale, 0.3, 1.6, false],
            [\extraVoiceProb, 0.0, 0.40, false],
            [\velocitySensitivity, 0.5, 1.6, false],
            [\reverbMix, 0.0, 0.55, false]
        ];

        spec.do { |item|
            var key, lo, hi, isInt, val, norm;
            key = item[0];
            lo = item[1];
            hi = item[2];
            isInt = item[3];
            val = ~sun[key];
            norm = val.linlin(lo, hi, 0, 1).clip(0, 1);

            if(~sun[\views][key].notNil) { ~sun[\views][key].value = norm };
            if(~sun[\labels][key].notNil) {
                ~sun[\labels][key].string = if(isInt) { val.asString } { val.round(0.001).asString };
            };
        };

        ~sun[\views][\arpButton].value = if(~sun[\arpEnabled]) { 0 } { 1 };
        ~sun[\updateReverb].value(~sun);
    };

    // --------------------------------------------------------
    // MIDI detection status
    // --------------------------------------------------------

    MIDIClient.init;
    MIDIIn.connectAll;

    if(MIDIClient.sources.isEmpty) {
        ~sun[\midiStatusText] = "No MIDI sources detected.";
    } {
        ~sun[\midiStatusText] = "Detected MIDI sources:";
        MIDIClient.sources.do { |src|
            ~sun[\midiStatusText] = ~sun[\midiStatusText]
            ++ "   ["
            ++ src.device
            ++ " | "
            ++ src.name
            ++ "]";
        };
    };

    ~sun[\views][\midiStatus].string = ~sun[\midiStatusText];

    // Connect to all MIDI sources by default
    ~sun[\connectMidi].value(~sun);
    ~sun[\refreshGui].value;

    // Meter updater
    ~sun[\meterUpdater] = Routine({
        loop {
            {
                if(~sun.notNil and: { ~sun[\views].notNil }) {
                    if(~sun[\views][\levelMeter].notNil) {
                        ~sun[\views][\levelMeter].value = ~sun[\lastLevel].clip(0.0, 1.0);
                    };
                    if(~sun[\views][\freqText].notNil) {
                        ~sun[\views][\freqText].string = (~sun[\lastFreq].round(0.1).asString ++ " Hz");
                    };
                };
            }.defer;
            0.08.wait;
        }
    }).play(AppClock);

    ~sun[\window].onClose = {
        if(~sun[\midiNoteOnDef].notNil) { ~sun[\midiNoteOnDef].free };
        if(~sun[\midiNoteOffDef].notNil) { ~sun[\midiNoteOffDef].free };
        if(~sun[\oscLevelDef].notNil) { ~sun[\oscLevelDef].free };
        if(~sun[\arpRoutine].notNil) { ~sun[\arpRoutine].stop };
        if(~sun[\meterUpdater].notNil) { ~sun[\meterUpdater].stop };

        ~sun[\activeNotes].keysValuesDo { |note, synth|
            if(synth.notNil) { synth.set(\gate, 0) };
        };

        if(~sun[\monitorSynth].notNil) { ~sun[\monitorSynth].free };
        if(~sun[\reverbSynth].notNil) { ~sun[\reverbSynth].free };
        if(~sun[\reverbBus].notNil) { ~sun[\reverbBus].free };
        if(~sun[\sourceGroup].notNil) { ~sun[\sourceGroup].free };
        if(~sun[\fxGroup].notNil) { ~sun[\fxGroup].free };
    };

    "Sun Arpeggios GUI ready.".postln;
};
)