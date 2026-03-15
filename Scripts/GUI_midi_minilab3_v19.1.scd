(
// ------------------------------------------------------------
// Sun Arpeggios V6.3 Minimal Fixed - MIDIdef Edition
// Working controls:
// - Split Point
// - Global Instrument
// - High Note Ceiling
// - Arp Rate
// - Global Dynamics
// - Reverb Mix
// - Signal Monitor
// ------------------------------------------------------------

MIDIdef.freeAll;
OSCdef.freeAll;

if(~sun.notNil and: { ~sun[\cleanup].notNil }) {
    ~sun[\cleanup].value(false);
};

s.waitForBoot {

    var makePanel, makeLabel, makeValue, makeSliderControl;

    // --------------------------------------------------------
    // Global state
    // --------------------------------------------------------

    ~sun = IdentityDictionary.new;

    ~sun[\appName] = "Sun Arpeggios";
    ~sun[\version] = "V6.3 Minimal Fixed";
    ~sun[\isCleaningUp] = false;
    ~sun[\guiMonitorActive] = false;
    ~sun[\quitServerOnClose] = true;

    ~sun[\views] = IdentityDictionary.new;
    ~sun[\labels] = IdentityDictionary.new;

    ~sun[\activeLowNotes] = IdentityDictionary.new;
    ~sun[\lowReleaseTokens] = IdentityDictionary.new;
    ~sun[\heldHigh] = IdentitySet.new;
    ~sun[\highVelocities] = IdentityDictionary.new;

    ~sun[\arpTask] = nil;
    ~sun[\levelOsc] = nil;
    ~sun[\fxSynth] = nil;
    ~sun[\monitorSynth] = nil;
    ~sun[\window] = nil;

    ~sun[\lastFreq] = 0.0;
    ~sun[\lastLevel] = 0.0;
    ~sun[\midiStatusText] = "Initializing MIDI...";

    ~sun[\lowHighSplit] = 60;
    ~sun[\highNoteCeiling] = 96;
    ~sun[\arpRate] = 0.095;
    ~sun[\dynamicScale] = 1.0;
    ~sun[\reverbMix] = 0.22;

    // Fixed internal values for minimal version
    ~sun[\reverbRoom] = 0.82;
    ~sun[\reverbDamp] = 0.50;
    ~sun[\lowDynamicScale] = 1.0;
    ~sun[\highDynamicScale] = 1.0;
    ~sun[\highFadeOut] = 2.8;
    ~sun[\highBrightnessScale] = 1.0;
    ~sun[\extraVoiceProb] = 0.16;
    ~sun[\lowNoteMaxHold] = 2.2;

    ~sun[\sourceBus] = Bus.audio(s, 2);
    ~sun[\sourceGroup] = Group.head(s);
    ~sun[\fxGroup] = Group.after(~sun[\sourceGroup]);

    // --------------------------------------------------------
    // Global instrument selector
    // --------------------------------------------------------

    ~sun[\instrumentPresets] = [
        (name: "Drone",  low: \sunLowDroneLP,    high: \sunHighDroneHP),
        (name: "Bright", low: \sunLowOrganBass,  high: \sunHighBrightArp),
        (name: "Glass",  low: \sunLowContraBass, high: \sunHighGlassArp)
    ];

    ~sun[\instrumentNames] = ~sun[\instrumentPresets].collect { |preset|
        preset[\name]
    };

    ~sun[\selectedInstrumentIndex] = 0;
    ~sun[\selectedLowInstrument] = ~sun[\instrumentPresets][0][\low];
    ~sun[\selectedHighInstrument] = ~sun[\instrumentPresets][0][\high];

    // --------------------------------------------------------
    // SynthDefs
    // --------------------------------------------------------

    SynthDef(\sunMasterReverb, {
        |inBus=0, out=0, mix=0.22, room=0.82, damp=0.50|
        var dry, wet, sig;

        dry = In.ar(inBus, 2);
        wet = FreeVerb.ar(dry, mix, room, damp);
        sig = XFade2.ar(dry, wet, mix.linlin(0, 1, -1, 1));
        sig = LeakDC.ar(sig);
        sig = Limiter.ar(sig, 0.92);

        Out.ar(out, sig);
    }).add;

    SynthDef(\sunLowDroneLP, {
        |out=0, freq=110, amp=0.15, gate=1, attack=0.08, release=1.8, cutoff=900|
        var snd, env, ffreq, rq;

        snd = { Gendy1.ar(1, 1, 1, 1, freq * 0.99, freq * 1.01) } ! 6;
        snd = Splay.ar(snd);

        ffreq = LFNoise2.kr(0.7).exprange((cutoff * 0.35).max(80), cutoff.max(120));
        rq = LFNoise2.kr(1.4).range(0.28, 0.78);

        env = EnvGen.kr(
            Env.asr(attack, 1, release),
            gate: gate,
            doneAction: 2
        );

        snd = snd * amp * env;
        snd = RLPF.ar(snd, ffreq, rq);
        snd = BLowShelf.ar(snd, 130, 0.8, 4);
        snd = tanh(LeakDC.ar(snd) * 1.15);

        Out.ar(out, snd);
    }).add;

    SynthDef(\sunLowOrganBass, {
        |out=0, freq=110, amp=0.15, gate=1, attack=0.08, release=1.8, cutoff=900|
        var env, sig;

        env = EnvGen.kr(
            Env.asr(attack, 1, release),
            gate: gate,
            doneAction: 2
        );

        sig = Mix([
            SinOsc.ar(freq * 0.5, 0, 0.22),
            VarSaw.ar(freq, 0, 0.45, 0.14),
            Pulse.ar(freq * 2, 0.5, 0.07),
            SinOsc.ar(freq, 0, 0.10)
        ]);

        sig = LPF.ar(sig, cutoff);
        sig = BLowShelf.ar(sig, 120, 0.8, 4);
        sig = tanh(LeakDC.ar(sig) * 1.25);

        Out.ar(out, Pan2.ar(sig * env * amp, 0));
    }).add;

    SynthDef(\sunLowContraBass, {
        |out=0, freq=110, amp=0.15, gate=1, attack=0.10, release=2.0, cutoff=850|
        var env, sig, bow;

        env = EnvGen.kr(
            Env.asr(attack, 1, release),
            gate: gate,
            doneAction: 2
        );

        bow = LPF.ar(WhiteNoise.ar(0.04), cutoff * 0.4)
            * EnvGen.kr(Env.perc(0.003, 0.08));

        sig = Mix([
            SinOsc.ar(freq * 0.5, 0, 0.18),
            VarSaw.ar(freq * 0.999, 0, 0.35, 0.11),
            VarSaw.ar(freq * 1.001, 0, 0.42, 0.11),
            SinOsc.ar(freq, 0, 0.10)
        ]) + bow;

        sig = LPF.ar(sig, cutoff);
        sig = BPeakEQ.ar(sig, (freq * 2).clip(80, 900), 0.6, 2.0);
        sig = BLowShelf.ar(sig, 110, 0.7, 5);
        sig = tanh(LeakDC.ar(sig) * 1.2);

        Out.ar(out, Pan2.ar(sig * env * amp, 0));
    }).add;

    SynthDef(\sunHighDroneHP, {
        |out=0, freq=440, amp=0.05, attack=0.0001, fadeOut=2.8, hpf=1400, lpf=7000, bright=0.6|
        var snd, env, ffreq, rq;

        snd = { Gendy1.ar(1, 1, 1, 1, freq * 0.99, freq * 1.01) } ! 6;
        snd = Splay.ar(snd);

        ffreq = LFNoise2.kr(2.1).exprange(hpf.max(300), (hpf * 2.3).clip(400, 9000));
        rq = LFNoise2.kr(3.2).range(0.25, 0.8);

        env = EnvGen.kr(
            Env.perc(attack, fadeOut, 1, curve: -4),
            doneAction: 2
        );

        snd = snd * amp * env;
        snd = RHPF.ar(snd, ffreq, rq);
        snd = LPF.ar(snd, lpf);
        snd = BPeakEQ.ar(snd, freq.clip(600, 3800), 0.45, bright);
        snd = tanh(LeakDC.ar(snd) * 0.95);

        Out.ar(out, snd);
    }).add;

    SynthDef(\sunHighBrightArp, {
        |out=0, freq=440, amp=0.05, attack=0.0001, fadeOut=2.8, hpf=1400, lpf=7000, bright=0.6|
        var env, tone, air, sig, safeFreq;

        safeFreq = freq.clip(120, 5000);

        env = EnvGen.kr(
            Env.perc(attack, fadeOut, 1, curve: -4),
            doneAction: 2
        );

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
        sig = tanh(LeakDC.ar(sig) * 0.85);
        sig = Splay.ar([sig, DelayC.ar(sig, 0.02, 0.0035)], 0.08);
        sig = Limiter.ar(sig, 0.8);

        Out.ar(out, sig * env * amp);
    }).add;

    SynthDef(\sunHighGlassArp, {
        |out=0, freq=440, amp=0.05, attack=0.0001, fadeOut=2.3, hpf=1400, lpf=6500, bright=0.6|
        var env, tone, shimmer, sig, safeFreq;

        safeFreq = freq.clip(120, 5000);

        env = EnvGen.kr(
            Env.perc(attack, fadeOut, 1, curve: -5),
            doneAction: 2
        );

        tone = Mix([
            SinOsc.ar(safeFreq, 0, 0.18),
            PMOsc.ar(safeFreq, safeFreq * 1.5, 2.2, 0, 0.10),
            SinOsc.ar(safeFreq * 2.01, 0, 0.05)
        ]);

        shimmer = HPF.ar(WhiteNoise.ar(0.008), hpf * 1.2)
            * EnvGen.kr(Env.perc(0.001, 0.05));

        sig = tone + shimmer;
        sig = HPF.ar(sig, hpf);
        sig = LPF.ar(sig, lpf);
        sig = BPeakEQ.ar(sig, safeFreq.clip(800, 4200), 0.5, bright * 0.8);
        sig = tanh(LeakDC.ar(sig) * 0.78);
        sig = Splay.ar([sig, DelayC.ar(sig, 0.03, 0.005)], 0.10);
        sig = Limiter.ar(sig, 0.75);

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

    ~sun[\fxSynth] = Synth.tail(~sun[\fxGroup], \sunMasterReverb, [
        \inBus, ~sun[\sourceBus],
        \out, 0,
        \mix, ~sun[\reverbMix],
        \room, ~sun[\reverbRoom],
        \damp, ~sun[\reverbDamp]
    ]);

    ~sun[\monitorSynth] = Synth.tail(~sun[\fxGroup], \sunOutputMonitor, [
        \inBus, ~sun[\sourceBus]
    ]);

    ~sun[\levelOsc] = OSCdef(\sunLevelWatcherV63, { |msg|
        if(~sun.notNil and: { msg.size > 3 }) {
            ~sun[\lastLevel] = msg[3].asFloat;
        };
    }, '/sunLevel');

    // --------------------------------------------------------
    // Helpers
    // --------------------------------------------------------

    ~sun[\updateReverb] = {
        if(~sun[\fxSynth].notNil) {
            ~sun[\fxSynth].set(
                \mix, ~sun[\reverbMix],
                \room, ~sun[\reverbRoom],
                \damp, ~sun[\reverbDamp]
            );
        };
    };

    ~sun[\applyInstrumentSelection] = { |index|
        var safeIndex, preset;

        safeIndex = index.clip(0, ~sun[\instrumentPresets].size - 1);
        preset = ~sun[\instrumentPresets][safeIndex];

        ~sun[\selectedInstrumentIndex] = safeIndex;
        ~sun[\selectedLowInstrument] = preset[\low];
        ~sun[\selectedHighInstrument] = preset[\high];

        if(~sun[\views][\instrumentPopup].notNil) {
            ~sun[\views][\instrumentPopup].value = safeIndex;
        };

        if(~sun[\views][\instrumentStatus].notNil) {
            ~sun[\views][\instrumentStatus].string = "Instrument: " ++ preset[\name];
        };
    };

    ~sun[\playLowVoice] = { |freq, amp, attack, release, cutoff|
        Synth(~sun[\selectedLowInstrument], [
            \out, ~sun[\sourceBus],
            \freq, freq,
            \amp, amp,
            \attack, attack,
            \release, release,
            \cutoff, cutoff
        ], ~sun[\sourceGroup]);
    };

    ~sun[\playHighVoice] = { |midiNote, vel, fadeScale=1.0|
        var amp, hpf, lpf, bright, fadeOut, ceilingRef, freq;

        ceilingRef = (~sun[\highNoteCeiling]).max(~sun[\lowHighSplit] + 1);
        freq = midiNote.midicps;

        amp = vel.linexp(1, 127, 0.010, 0.085);
        amp = amp * midiNote.linlin(~sun[\lowHighSplit], ceilingRef, 1.0, 0.45);
        amp = amp * ~sun[\highDynamicScale] * ~sun[\dynamicScale];
        amp = amp.clip(0.008, 0.11);

        hpf = midiNote.linexp(~sun[\lowHighSplit], ceilingRef, 850, 3000).clip(850, 3000);

        lpf = midiNote.linexp(~sun[\lowHighSplit], ceilingRef, 7600, 3800);
        lpf = (lpf * vel.linexp(1, 127, 0.85, 1.20)).clip(3500, 9000);

        bright = midiNote.linlin(~sun[\lowHighSplit], ceilingRef, 0.9, 0.15);
        bright = bright * vel.linlin(1, 127, 0.7, 1.45);
        bright = (bright * ~sun[\highBrightnessScale]).clip(0.05, 1.8);

        fadeOut = vel.linlin(1, 127, ~sun[\highFadeOut] * 1.15, ~sun[\highFadeOut] * 0.75);
        fadeOut = (fadeOut * fadeScale).clip(0.35, 5.0);

        ~sun[\lastFreq] = freq;

        Synth(~sun[\selectedHighInstrument], [
            \out, ~sun[\sourceBus],
            \freq, freq,
            \amp, amp,
            \attack, 0.0001,
            \fadeOut, fadeOut,
            \hpf, hpf,
            \lpf, lpf,
            \bright, bright
        ], ~sun[\sourceGroup]);
    };

    ~sun[\stopLowNote] = { |note, forced=false|
        var synth, token;

        token = (~sun[\lowReleaseTokens].at(note) ? 0) + 1;
        ~sun[\lowReleaseTokens].put(note, token);

        synth = ~sun[\activeLowNotes].removeAt(note);
        if(synth.notNil) {
            synth.set(\gate, if(forced) { -1.1 } { 0 });
        };
    };

    ~sun[\scheduleLowRelease] = { |note|
        var token;

        token = (~sun[\lowReleaseTokens].at(note) ? 0) + 1;
        ~sun[\lowReleaseTokens].put(note, token);

        SystemClock.sched(~sun[\lowNoteMaxHold], {
            if(
                ~sun.notNil
                and: { ~sun[\isCleaningUp].not }
                and: { ~sun[\lowReleaseTokens].at(note) == token }
            ) {
                ~sun[\stopLowNote].value(note, true);
            };
            nil
        });
    };

    ~sun[\stopArp] = {
        if(~sun[\heldHigh].isEmpty and: { ~sun[\arpTask].notNil }) {
            ~sun[\arpTask].stop;
            ~sun[\arpTask] = nil;
        };
    };

    ~sun[\startArp] = {
        if(~sun[\arpTask].isNil) {
            ~sun[\arpTask] = Task({
                var notes, baseNote, octaveShift, midiNote, vel, extraVoice;
                var extraBase, extraVel;

                loop {
                    notes = ~sun[\heldHigh].asArray.sort;

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

                        midiNote = (baseNote + octaveShift).min(~sun[\highNoteCeiling]);
                        vel = ~sun[\highVelocities].at(baseNote);
                        if(vel.isNil) { vel = 100 };

                        ~sun[\playHighVoice].value(midiNote, vel, 1.0);

                        extraVoice = ~sun[\extraVoiceProb].coin and: { notes.size > 1 };
                        if(extraVoice) {
                            extraBase = notes.choose;
                            extraVel = ~sun[\highVelocities].at(extraBase);
                            if(extraVel.isNil) { extraVel = 100 };

                            octaveShift = if(extraBase >= 79) {
                                [0, 12].wchoose([0.7, 0.3]);
                            } {
                                [12, 24].wchoose([0.75, 0.25]);
                            };

                            midiNote = (extraBase + octaveShift).min(~sun[\highNoteCeiling]);
                            ~sun[\playHighVoice].value(midiNote, extraVel, 0.75);
                        };
                    };

                    (~sun[\arpRate]).wait;
                }
            }).play(SystemClock);
        };
    };

    ~sun[\processNoteOn] = { |vel, note|
        var freq, synth, amp, attack, release, cutoff, splitTop;

        splitTop = (~sun[\lowHighSplit] - 1).max(25);

        if(note < ~sun[\lowHighSplit]) {
            ~sun[\stopLowNote].value(note, true);

            freq = note.midicps;
            ~sun[\lastFreq] = freq;

            amp = vel.linexp(1, 127, 0.025, 0.22);
            amp = (amp * ~sun[\lowDynamicScale] * ~sun[\dynamicScale]).clip(0.015, 0.30);

            attack = vel.linlin(1, 127, 0.18, 0.05);
            attack = (attack * note.linlin(24, splitTop, 1.1, 0.9)).clip(0.04, 0.22);

            release = vel.linlin(1, 127, 3.2, 1.6).clip(1.2, 3.5);

            cutoff = note.linexp(24, splitTop, 220, 900);
            cutoff = (cutoff * vel.linlin(1, 127, 0.55, 1.35)).clip(220, 1500);

            synth = ~sun[\playLowVoice].value(freq, amp, attack, release, cutoff);
            ~sun[\activeLowNotes].put(note, synth);
            ~sun[\scheduleLowRelease].value(note);
        } {
            ~sun[\heldHigh].add(note);
            ~sun[\highVelocities].put(note, vel);
            ~sun[\startArp].value;
        };
    };

    ~sun[\processNoteOff] = { |note|
        ~sun[\heldHigh].remove(note);
        ~sun[\highVelocities].removeAt(note);
        ~sun[\stopLowNote].value(note, false);
        ~sun[\stopArp].value;
    };

    ~sun[\connectMidi] = {
        MIDIdef.freeAll;
        MIDIIn.noteOnZeroAsNoteOff = true;

        MIDIdef.noteOn(\sunNoteOnMinimal, { |vel, note, chan, src|
            if(~sun.notNil and: { ~sun[\isCleaningUp].not }) {
                ~sun[\processNoteOn].value(vel, note);
            };
        });

        MIDIdef.noteOff(\sunNoteOffMinimal, { |vel, note, chan, src|
            if(~sun.notNil and: { ~sun[\isCleaningUp].not }) {
                ~sun[\processNoteOff].value(note);
            };
        });
    };

    ~sun[\setParam] = { |key, value|
        switch(key,
            \lowHighSplit, {
                ~sun[\lowHighSplit] = value.round(1).asInteger.clip(48, 72);
                if(~sun[\highNoteCeiling] <= ~sun[\lowHighSplit]) {
                    ~sun[\highNoteCeiling] = (~sun[\lowHighSplit] + 1).clip(84, 108);
                };
            },
            \highNoteCeiling, {
                ~sun[\highNoteCeiling] = value.round(1).asInteger.clip(84, 108);
                if(~sun[\highNoteCeiling] <= ~sun[\lowHighSplit]) {
                    ~sun[\highNoteCeiling] = (~sun[\lowHighSplit] + 1).clip(84, 108);
                };
            },
            \arpRate, {
                ~sun[\arpRate] = value.clip(0.05, 0.22);
            },
            \dynamicScale, {
                ~sun[\dynamicScale] = value.clip(0.4, 1.7);
            },
            \reverbMix, {
                ~sun[\reverbMix] = value.clip(0.0, 0.55);
                ~sun[\updateReverb].value;
            }
        );

        ~sun[\refreshGui].value;
    };

    ~sun[\refreshGui] = {
        if(~sun[\views][\lowHighSplit].notNil) {
            ~sun[\views][\lowHighSplit].value = ~sun[\lowHighSplit].linlin(48, 72, 0, 1).clip(0, 1);
        };
        if(~sun[\labels][\lowHighSplit].notNil) {
            ~sun[\labels][\lowHighSplit].string = ~sun[\lowHighSplit].asString;
        };

        if(~sun[\views][\highNoteCeiling].notNil) {
            ~sun[\views][\highNoteCeiling].value = ~sun[\highNoteCeiling].linlin(84, 108, 0, 1).clip(0, 1);
        };
        if(~sun[\labels][\highNoteCeiling].notNil) {
            ~sun[\labels][\highNoteCeiling].string = ~sun[\highNoteCeiling].asString;
        };

        if(~sun[\views][\arpRate].notNil) {
            ~sun[\views][\arpRate].value = ~sun[\arpRate].linlin(0.05, 0.22, 0, 1).clip(0, 1);
        };
        if(~sun[\labels][\arpRate].notNil) {
            ~sun[\labels][\arpRate].string = ~sun[\arpRate].round(0.001).asString;
        };

        if(~sun[\views][\dynamicScale].notNil) {
            ~sun[\views][\dynamicScale].value = ~sun[\dynamicScale].linlin(0.4, 1.7, 0, 1).clip(0, 1);
        };
        if(~sun[\labels][\dynamicScale].notNil) {
            ~sun[\labels][\dynamicScale].string = ~sun[\dynamicScale].round(0.001).asString;
        };

        if(~sun[\views][\reverbMix].notNil) {
            ~sun[\views][\reverbMix].value = ~sun[\reverbMix].linlin(0.0, 0.55, 0, 1).clip(0, 1);
        };
        if(~sun[\labels][\reverbMix].notNil) {
            ~sun[\labels][\reverbMix].string = ~sun[\reverbMix].round(0.001).asString;
        };

        if(~sun[\views][\splitStatus].notNil) {
            ~sun[\views][\splitStatus].string =
            "Low: notes < " ++ ~sun[\lowHighSplit].asString
            ++ "    |    High: notes >= " ++ ~sun[\lowHighSplit].asString;
        };

        ~sun[\applyInstrumentSelection].value(~sun[\selectedInstrumentIndex]);
    };

    ~sun[\startGuiMonitor] = {
        if(~sun[\guiMonitorActive].not) {
            ~sun[\guiMonitorActive] = true;

            AppClock.sched(0.0, {
                if(~sun.isNil or: { ~sun[\guiMonitorActive].not }) {
                    nil
                } {
                    if(~sun[\views][\levelMeter].notNil) {
                        ~sun[\views][\levelMeter].value = ~sun[\lastLevel].clip(0.0, 1.0);
                    };

                    if(~sun[\views][\freqText].notNil) {
                        ~sun[\views][\freqText].string = ~sun[\lastFreq].round(0.1).asString ++ " Hz";
                    };

                    if(~sun[\views][\instrumentStatus].notNil) {
                        ~sun[\views][\instrumentStatus].string =
                        "Instrument: " ++ ~sun[\instrumentNames][~sun[\selectedInstrumentIndex]];
                    };

                    if(~sun[\views][\midiStatus].notNil) {
                        ~sun[\views][\midiStatus].string = ~sun[\midiStatusText];
                    };

                    0.08
                }
            });
        };
    };

    ~sun[\resetControls] = {
        ~sun[\lowHighSplit] = 60;
        ~sun[\highNoteCeiling] = 96;
        ~sun[\arpRate] = 0.095;
        ~sun[\dynamicScale] = 1.0;
        ~sun[\reverbMix] = 0.22;

        ~sun[\reverbRoom] = 0.82;
        ~sun[\reverbDamp] = 0.50;
        ~sun[\lowDynamicScale] = 1.0;
        ~sun[\highDynamicScale] = 1.0;
        ~sun[\highFadeOut] = 2.8;
        ~sun[\highBrightnessScale] = 1.0;
        ~sun[\extraVoiceProb] = 0.16;
        ~sun[\lowNoteMaxHold] = 2.2;

        ~sun[\applyInstrumentSelection].value(0);
        ~sun[\updateReverb].value;
        ~sun[\refreshGui].value;
    };

    ~sun[\cleanup] = { |quitServer=false|
        if(~sun.isNil) { ^nil };
        if(~sun[\isCleaningUp]) { ^nil };

        ~sun[\isCleaningUp] = true;
        ~sun[\guiMonitorActive] = false;

        MIDIdef.freeAll;

        if(~sun[\levelOsc].notNil) {
            ~sun[\levelOsc].free;
            ~sun[\levelOsc] = nil;
        };

        if(~sun[\arpTask].notNil) {
            ~sun[\arpTask].stop;
            ~sun[\arpTask] = nil;
        };

        ~sun[\lowReleaseTokens].clear;

        ~sun[\activeLowNotes].keysValuesDo { |note, synth|
            if(synth.notNil) {
                synth.set(\gate, -1.1);
            };
        };
        ~sun[\activeLowNotes].clear;

        ~sun[\heldHigh].clear;
        ~sun[\highVelocities].clear;

        if(~sun[\monitorSynth].notNil) {
            ~sun[\monitorSynth].free;
            ~sun[\monitorSynth] = nil;
        };

        if(~sun[\fxSynth].notNil) {
            ~sun[\fxSynth].free;
            ~sun[\fxSynth] = nil;
        };

        if(~sun[\sourceGroup].notNil) {
            ~sun[\sourceGroup].freeAll;
            ~sun[\sourceGroup].free;
            ~sun[\sourceGroup] = nil;
        };

        if(~sun[\fxGroup].notNil) {
            ~sun[\fxGroup].freeAll;
            ~sun[\fxGroup].free;
            ~sun[\fxGroup] = nil;
        };

        if(~sun[\sourceBus].notNil) {
            ~sun[\sourceBus].free;
            ~sun[\sourceBus] = nil;
        };

        if(quitServer and: { s.serverRunning }) {
            s.freeAll;
            s.quit;
        };

        ~sun = nil;
    };

    // --------------------------------------------------------
    // GUI helpers
    // --------------------------------------------------------

    makePanel = { |parent, x, y, w, h, title|
        var panel;

        panel = CompositeView(parent, Rect(x, y, w, h));
        panel.background = Color(0.14, 0.14, 0.17);

        StaticText(panel, Rect(12, 8, w - 24, 22))
            .string_(title)
            .stringColor_(Color.white)
            .font_(Font("Arial", 12, true));

        panel;
    };

    makeLabel = { |parent, x, y, w, h, text|
        StaticText(parent, Rect(x, y, w, h))
            .string_(text)
            .stringColor_(Color.white)
            .font_(Font("Arial", 10));
    };

    makeValue = { |parent, x, y, w, h, text=""|
        StaticText(parent, Rect(x, y, w, h))
            .string_(text)
            .align_(\right)
            .stringColor_(Color(0.82, 0.92, 1.0))
            .font_(Font("Arial", 10));
    };

    makeSliderControl = { |panel, key, title, y, lo, hi, isInt=false|
        var valueLabel, slider;

        makeLabel.(panel, 14, y, 160, 18, title);
        valueLabel = makeValue.(panel, 220, y, 70, 18, "");

        slider = Slider(panel, Rect(14, y + 20, 276, 20))
            .background_(Color(0.18, 0.18, 0.22))
            .knobColor_(Color(0.30, 0.60, 0.95))
            .action_({ |sl|
                var mapped;
                mapped = sl.value.linlin(0, 1, lo, hi);
                if(isInt) { mapped = mapped.round(1).asInteger };
                ~sun[\setParam].value(key, mapped);
            });

        ~sun[\views][key] = slider;
        ~sun[\labels][key] = valueLabel;
    };

    // --------------------------------------------------------
    // GUI
    // --------------------------------------------------------

    ~sun[\window] = Window(
        "Sun Arpeggios — " ++ ~sun[\version],
        Rect(80, 60, 980, 520)
    ).front;

    ~sun[\window].background = Color(0.10, 0.10, 0.12);

    StaticText(~sun[\window], Rect(20, 14, 500, 28))
        .string_("Sun Arpeggios — Performance Interface")
        .font_(Font("Arial", 18, true))
        .stringColor_(Color.white);

    ~statusPanel      = makePanel.(~sun[\window], 20, 56, 940, 86, "System Status");
    ~instrumentPanel  = makePanel.(~sun[\window], 20, 156, 300, 210, "Split and Instrument");
    ~performancePanel = makePanel.(~sun[\window], 340, 156, 300, 270, "Performance Parameters");
    ~monitorPanel     = makePanel.(~sun[\window], 660, 156, 300, 210, "Signal Monitor");

    makeLabel.(~statusPanel, 14, 34, 120, 18, "MIDI Detection");

    ~sun[\views][\midiStatus] = StaticText(~statusPanel, Rect(14, 56, 760, 18))
        .string_("Initializing MIDI...")
        .stringColor_(Color(0.82, 0.92, 1.0))
        .font_(Font("Arial", 10));

    ~sun[\views][\resetBtn] = Button(~statusPanel, Rect(810, 14, 110, 28))
        .states_([["Reset", Color.white, Color(0.40, 0.25, 0.25)]])
        .action_({
            ~sun[\resetControls].value;
        });

    makeSliderControl.(~instrumentPanel, \lowHighSplit, "Split Point", 38, 48, 72, true);

    ~sun[\views][\splitStatus] = StaticText(~instrumentPanel, Rect(14, 90, 276, 18))
        .string_("")
        .stringColor_(Color(0.82, 0.92, 1.0))
        .font_(Font("Arial", 9));

    makeLabel.(~instrumentPanel, 14, 126, 170, 18, "Global Instrument");

    ~sun[\views][\instrumentPopup] = PopUpMenu(~instrumentPanel, Rect(14, 148, 276, 24))
        .items_(~sun[\instrumentNames])
        .background_(Color(0.20, 0.20, 0.24))
        .stringColor_(Color.white)
        .action_({ |menu|
            ~sun[\applyInstrumentSelection].value(menu.value);
        });

    makeSliderControl.(~performancePanel, \highNoteCeiling, "High Note Ceiling", 38, 84, 108, true);
    makeSliderControl.(~performancePanel, \arpRate, "Arp Rate", 96, 0.05, 0.22, false);
    makeSliderControl.(~performancePanel, \dynamicScale, "Global Dynamics", 154, 0.4, 1.7, false);
    makeSliderControl.(~performancePanel, \reverbMix, "Reverb Mix", 212, 0.0, 0.55, false);

    makeLabel.(~monitorPanel, 14, 38, 100, 18, "Level");

    ~sun[\views][\levelMeter] = LevelIndicator(~monitorPanel, Rect(14, 60, 272, 20))
        .warning_(0.65)
        .critical_(0.85)
        .drawsPeak_(true)
        .numTicks_(12)
        .background_(Color(0.16, 0.16, 0.18))
        .value_(0);

    makeLabel.(~monitorPanel, 14, 98, 130, 18, "Estimated Frequency");

    ~sun[\views][\freqText] = StaticText(~monitorPanel, Rect(14, 120, 272, 18))
        .string_("0.0 Hz")
        .stringColor_(Color(0.82, 0.92, 1.0))
        .font_(Font("Arial", 11));

    makeLabel.(~monitorPanel, 14, 154, 130, 18, "Current Instrument");

    ~sun[\views][\instrumentStatus] = StaticText(~monitorPanel, Rect(14, 176, 272, 18))
        .string_("")
        .stringColor_(Color(0.82, 0.92, 1.0))
        .font_(Font("Arial", 10));

    // --------------------------------------------------------
    // MIDI init
    // --------------------------------------------------------

    MIDIClient.init;
    MIDIIn.connectAll;

    if(MIDIClient.sources.isEmpty) {
        ~sun[\midiStatusText] = "No MIDI sources detected.";
    } {
        ~sun[\midiStatusText] = "Detected MIDI sources: " ++
        MIDIClient.sources.collect { |src|
            src.device ++ " | " ++ src.name
        }.join("    ||    ");
    };

    ~sun[\connectMidi].value;
    ~sun[\refreshGui].value;
    ~sun[\startGuiMonitor].value;

    ~sun[\window].onClose = {
        ~sun[\cleanup].value(~sun[\quitServerOnClose]);
    };

    "Sun Arpeggios V6.3 Minimal Fixed ready.".postln;
};
)