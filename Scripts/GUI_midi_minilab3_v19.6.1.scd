(
// ------------------------------------------------------------
// Sun Arpeggios V6.6 Beta Public - Separate Tail and Reverb
// Working controls:
// - Global Instrument
// - High Note Ceiling
// - Arp Rate
// - Global Dynamics
// - Tail / Staccato
// - Reverb Mix
// - Signal Monitor
// ------------------------------------------------------------

if(MIDIdef(\sunBetaNoteOnV66).notNil) { MIDIdef(\sunBetaNoteOnV66).free; };
if(MIDIdef(\sunBetaNoteOffV66).notNil) { MIDIdef(\sunBetaNoteOffV66).free; };
if(OSCdef(\sunLevelWatcherV66).notNil) { OSCdef(\sunLevelWatcherV66).free; };

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
    ~sun[\version] = "V6.6 Beta Public";
    ~sun[\isCleaningUp] = false;
    ~sun[\guiMonitorActive] = false;
    ~sun[\quitServerOnClose] = true;

    ~sun[\views] = IdentityDictionary.new;
    ~sun[\labels] = IdentityDictionary.new;

    ~sun[\heldNotes] = IdentitySet.new;
    ~sun[\noteVelocities] = IdentityDictionary.new;

    ~sun[\arpTask] = nil;
    ~sun[\levelOsc] = nil;
    ~sun[\fxSynth] = nil;
    ~sun[\monitorSynth] = nil;
    ~sun[\window] = nil;

    ~sun[\lastFreq] = 0.0;
    ~sun[\lastLevel] = 0.0;
    ~sun[\midiStatusText] = "Initializing MIDI...";

    ~sun[\highNoteCeiling] = 96;
    ~sun[\arpRate] = 0.095;
    ~sun[\dynamicScale] = 1.0;
    ~sun[\tailAmount] = 0.45;   // 0 = staccato, 1 = long
    ~sun[\reverbMix] = 0.22;    // 0 = dry, 1 = wet

    // Fixed internal values
    ~sun[\reverbRoom] = 0.82;
    ~sun[\reverbDamp] = 0.50;
    ~sun[\highFadeOut] = 2.9;
    ~sun[\highBrightnessScale] = 1.0;
    ~sun[\extraVoiceProb] = 0.16;

    ~sun[\sourceBus] = Bus.audio(s, 2);
    ~sun[\monitorBus] = Bus.audio(s, 2);
    ~sun[\sourceGroup] = Group.head(s);
    ~sun[\fxGroup] = Group.after(~sun[\sourceGroup]);

    // --------------------------------------------------------
    // Global instrument selector
    // --------------------------------------------------------

    ~sun[\instrumentPresets] = [
        (name: "Drone",        key: \sunArpDrone),
        (name: "Bright",       key: \sunArpBright),
        (name: "Glass",        key: \sunArpGlass),
        (name: "Church Organ", key: \sunArpChurchOrgan)
    ];

    ~sun[\instrumentNames] = ~sun[\instrumentPresets].collect { |preset|
        preset[\name]
    };

    ~sun[\selectedInstrumentIndex] = 0;
    ~sun[\selectedInstrument] = ~sun[\instrumentPresets][0][\key];

    // --------------------------------------------------------
    // SynthDefs
    // --------------------------------------------------------

    SynthDef(\sunMasterReverb, {
        |inBus=0, out=0, monitorBus=0, mix=0.22, room=0.82, damp=0.50|
        var dry, wetOnly, sig, wetGain;

        dry = In.ar(inBus, 2);

        wetOnly = FreeVerb.ar(dry, 1.0, room, damp);
        wetGain = mix.linlin(0.0, 1.0, 0.0, 1.35).clip(0.0, 1.35);

        sig = (dry * (1 - mix)) + (wetOnly * wetGain);

        sig = LeakDC.ar(sig);
        sig = Limiter.ar(sig, 0.92);

        Out.ar(monitorBus, sig);
        Out.ar(out, sig);
    }).add;

    SynthDef(\sunArpDrone, {
        |out=0, freq=220, amp=0.06, attack=0.001, fadeOut=2.8, bright=0.7|
        var env, snd, lpf;

        env = EnvGen.kr(
            Env.perc(attack.max(0.001), fadeOut, 1, curve: -4),
            doneAction: 2
        );

        snd = { Gendy1.ar(1, 1, 1, 1, freq * 0.995, freq * 1.005) } ! 4;
        snd = Splay.ar(snd, 0.12);

        lpf = (freq * (3.5 + (bright * 3.0))).clip(250, 9000);
        snd = LPF.ar(snd, lpf);
        snd = BPeakEQ.ar(snd, freq.clip(80, 3500), 0.4, bright * 0.8);
        snd = tanh(LeakDC.ar(snd) * 0.95);

        Out.ar(out, snd * env * amp);
    }).add;

    SynthDef(\sunArpBright, {
        |out=0, freq=220, amp=0.06, attack=0.001, fadeOut=2.6, bright=0.8|
        var env, tone, sig, safeFreq, lpf;

        safeFreq = freq.clip(40, 5000);

        env = EnvGen.kr(
            Env.perc(attack.max(0.001), fadeOut, 1, curve: -4),
            doneAction: 2
        );

        tone = Mix([
            Pulse.ar(safeFreq, 0.45, 0.10),
            VarSaw.ar(safeFreq * 1.003, 0, 0.30, 0.06),
            SinOsc.ar(safeFreq * 2.0, 0, 0.04)
        ]);

        lpf = (safeFreq * (5.0 + bright * 4.5)).clip(400, 11000);
        sig = LPF.ar(tone, lpf);
        sig = BPeakEQ.ar(sig, safeFreq.clip(120, 4200), 0.45, bright);
        sig = tanh(LeakDC.ar(sig) * 0.88);
        sig = Pan2.ar(sig, 0);

        Out.ar(out, sig * env * amp);
    }).add;

    SynthDef(\sunArpGlass, {
        |out=0, freq=220, amp=0.055, attack=0.001, fadeOut=2.3, bright=0.8|
        var env, tone, shimmer, sig, safeFreq, lpf;

        safeFreq = freq.clip(40, 5000);

        env = EnvGen.kr(
            Env.perc(attack.max(0.001), fadeOut, 1, curve: -5),
            doneAction: 2
        );

        tone = Mix([
            SinOsc.ar(safeFreq, 0, 0.20),
            PMOsc.ar(safeFreq, safeFreq * 1.5, 2.2, 0, 0.11),
            SinOsc.ar(safeFreq * 2.01, 0, 0.05)
        ]);

        shimmer = HPF.ar(WhiteNoise.ar(0.008), (safeFreq * 2.0).clip(300, 7000))
            * EnvGen.kr(Env.perc(0.001, 0.05));

        lpf = (safeFreq * (6.0 + bright * 5.0)).clip(500, 12000);
        sig = tone + shimmer;
        sig = LPF.ar(sig, lpf);
        sig = BPeakEQ.ar(sig, safeFreq.clip(150, 4500), 0.5, bright * 0.9);
        sig = tanh(LeakDC.ar(sig) * 0.80);
        sig = Pan2.ar(sig, 0);

        Out.ar(out, sig * env * amp);
    }).add;

    SynthDef(\sunArpChurchOrgan, {
        |out=0, freq=220, amp=0.06, attack=0.004, fadeOut=3.2, bright=0.85|
        var env, safeFreq, vib, foundation, mixtures, chiff, sig, body;

        safeFreq = freq.clip(35, 5000);
        vib = SinOsc.kr(4.8, 0, 0.002, 1.0);

        env = EnvGen.kr(
            Env.perc(attack.max(0.002), fadeOut, 1, curve: -3),
            doneAction: 2
        );

        foundation = Mix([
            SinOsc.ar(safeFreq * 0.5 * vib, 0, 0.20),
            SinOsc.ar(safeFreq * 1.0 * vib, 0, 0.36),
            SinOsc.ar(safeFreq * 2.0 * vib, 0, 0.18)
        ]);

        mixtures = Mix([
            SinOsc.ar(safeFreq * 3.0, 0, 0.10),
            SinOsc.ar(safeFreq * 4.0, 0, 0.08),
            SinOsc.ar(safeFreq * 5.0, 0, 0.05),
            Pulse.ar(safeFreq * 2.666, 0.5, 0.05),
            Pulse.ar(safeFreq * 5.333, 0.5, 0.03)
        ]);

        chiff = HPF.ar(WhiteNoise.ar(0.012), 1800)
            * EnvGen.kr(Env.perc(0.001, 0.018));

        sig = foundation + mixtures + chiff;
        body = BPeakEQ.ar(sig, (safeFreq * 2).clip(90, 2600), 0.45, 2.0);
        body = BPeakEQ.ar(body, (safeFreq * 4).clip(150, 4200), 0.35, 1.3);

        sig = LPF.ar(body, (safeFreq * (7.0 + bright * 3.5)).clip(1200, 10000));
        sig = BLowShelf.ar(sig, 140, 0.8, 2.5);
        sig = BPeakEQ.ar(sig, safeFreq.clip(100, 3200), 0.35, bright * 0.55);
        sig = LeakDC.ar(sig);
        sig = tanh(sig * 0.78);
        sig = Pan2.ar(sig, 0);

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
        \monitorBus, ~sun[\monitorBus],
        \mix, ~sun[\reverbMix],
        \room, ~sun[\reverbRoom],
        \damp, ~sun[\reverbDamp]
    ]);

    ~sun[\monitorSynth] = Synth.tail(~sun[\fxGroup], \sunOutputMonitor, [
        \inBus, ~sun[\monitorBus]
    ]);

    ~sun[\levelOsc] = OSCdef(\sunLevelWatcherV66, { |msg|
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
        ~sun[\selectedInstrument] = preset[\key];

        if(~sun[\views][\instrumentPopup].notNil) {
            ~sun[\views][\instrumentPopup].value = safeIndex;
        };

        if(~sun[\views][\instrumentStatus].notNil) {
            ~sun[\views][\instrumentStatus].string = "Instrument: " ++ preset[\name];
        };
    };

    ~sun[\playArpVoice] = { |midiNote, vel, fadeScale=1.0|
        var amp, bright, fadeOut, freq, articulationScale;

        freq = midiNote.midicps;

        amp = vel.linexp(1, 127, 0.014, 0.085);
        amp = (amp * ~sun[\dynamicScale]).clip(0.012, 0.11);

        bright = vel.linlin(1, 127, 0.75, 1.20);
        bright = (bright * ~sun[\highBrightnessScale]).clip(0.4, 1.5);

        fadeOut = vel.linlin(1, 127, ~sun[\highFadeOut] * 1.15, ~sun[\highFadeOut] * 0.90);

        // Independent articulation control
        // 0.0 = staccato, 1.0 = long tail
        articulationScale = ~sun[\tailAmount].linlin(0.0, 1.0, 0.10, 1.0).clip(0.10, 1.0);
        fadeOut = (fadeOut * fadeScale * articulationScale).clip(0.10, 5.5);

        ~sun[\lastFreq] = freq;

        Synth(~sun[\selectedInstrument], [
            \out, ~sun[\sourceBus],
            \freq, freq,
            \amp, amp,
            \attack, 0.001,
            \fadeOut, fadeOut,
            \bright, bright
        ], ~sun[\sourceGroup]);
    };

    ~sun[\stopArp] = {
        if(~sun[\heldNotes].isEmpty and: { ~sun[\arpTask].notNil }) {
            ~sun[\arpTask].stop;
            ~sun[\arpTask] = nil;
        };
    };

    ~sun[\startArp] = {
        if(~sun[\arpTask].isNil) {
            ~sun[\arpTask] = Task({
                var notes, baseNote, octaveShift, midiNote, vel, extraVoice;
                var extraBase, extraVel, ceiling;

                loop {
                    notes = ~sun[\heldNotes].asArray.sort;
                    ceiling = ~sun[\highNoteCeiling];

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

                        midiNote = baseNote + octaveShift;
                        if(baseNote <= ceiling) {
                            midiNote = midiNote.min(ceiling);
                        } {
                            midiNote = baseNote;
                        };

                        vel = ~sun[\noteVelocities].at(baseNote);
                        if(vel.isNil) { vel = 100 };

                        ~sun[\playArpVoice].value(midiNote, vel, 1.0);

                        extraVoice = ~sun[\extraVoiceProb].coin and: { notes.size > 1 };
                        if(extraVoice) {
                            extraBase = notes.choose;
                            extraVel = ~sun[\noteVelocities].at(extraBase);
                            if(extraVel.isNil) { extraVel = 100 };

                            octaveShift = if(extraBase >= 79) {
                                [0, 12].wchoose([0.7, 0.3]);
                            } {
                                [12, 24].wchoose([0.75, 0.25]);
                            };

                            midiNote = extraBase + octaveShift;
                            if(extraBase <= ceiling) {
                                midiNote = midiNote.min(ceiling);
                            } {
                                midiNote = extraBase;
                            };

                            ~sun[\playArpVoice].value(midiNote, extraVel, 0.75);
                        };
                    };

                    (~sun[\arpRate]).wait;
                }
            }).play(SystemClock);
        };
    };

    ~sun[\processNoteOn] = { |vel, note|
        ~sun[\heldNotes].add(note);
        ~sun[\noteVelocities].put(note, vel);
        ~sun[\startArp].value;
    };

    ~sun[\processNoteOff] = { |note|
        ~sun[\heldNotes].remove(note);
        ~sun[\noteVelocities].removeAt(note);
        ~sun[\stopArp].value;
    };

    ~sun[\connectMidi] = {
        if(MIDIdef(\sunBetaNoteOnV66).notNil) { MIDIdef(\sunBetaNoteOnV66).free; };
        if(MIDIdef(\sunBetaNoteOffV66).notNil) { MIDIdef(\sunBetaNoteOffV66).free; };

        MIDIIn.noteOnZeroAsNoteOff = true;

        MIDIdef.noteOn(\sunBetaNoteOnV66, { |vel, note, chan, src|
            if(~sun.notNil and: { ~sun[\isCleaningUp].not }) {
                ~sun[\processNoteOn].value(vel, note);
            };
        });

        MIDIdef.noteOff(\sunBetaNoteOffV66, { |vel, note, chan, src|
            if(~sun.notNil and: { ~sun[\isCleaningUp].not }) {
                ~sun[\processNoteOff].value(note);
            };
        });
    };

    ~sun[\setParam] = { |key, value|
        switch(key,
            \highNoteCeiling, {
                ~sun[\highNoteCeiling] = value.round(1).asInteger.clip(84, 108);
            },
            \arpRate, {
                ~sun[\arpRate] = value.clip(0.05, 0.22);
            },
            \dynamicScale, {
                ~sun[\dynamicScale] = value.clip(0.4, 1.7);
            },
            \tailAmount, {
                ~sun[\tailAmount] = value.clip(0.0, 1.0);
            },
            \reverbMix, {
                ~sun[\reverbMix] = value.clip(0.0, 1.0);
                ~sun[\updateReverb].value;
            }
        );

        ~sun[\refreshGui].value;
    };

    ~sun[\refreshGui] = {
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

        if(~sun[\views][\tailAmount].notNil) {
            ~sun[\views][\tailAmount].value = ~sun[\tailAmount].clip(0, 1);
        };
        if(~sun[\labels][\tailAmount].notNil) {
            ~sun[\labels][\tailAmount].string = ~sun[\tailAmount].round(0.001).asString;
        };

        if(~sun[\views][\reverbMix].notNil) {
            ~sun[\views][\reverbMix].value = ~sun[\reverbMix].clip(0, 1);
        };
        if(~sun[\labels][\reverbMix].notNil) {
            ~sun[\labels][\reverbMix].string = ~sun[\reverbMix].round(0.001).asString;
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
        ~sun[\highNoteCeiling] = 96;
        ~sun[\arpRate] = 0.095;
        ~sun[\dynamicScale] = 1.0;
        ~sun[\tailAmount] = 0.45;
        ~sun[\reverbMix] = 0.22;

        ~sun[\reverbRoom] = 0.82;
        ~sun[\reverbDamp] = 0.50;
        ~sun[\highFadeOut] = 2.9;
        ~sun[\highBrightnessScale] = 1.0;
        ~sun[\extraVoiceProb] = 0.16;

        ~sun[\applyInstrumentSelection].value(0);
        ~sun[\updateReverb].value;
        ~sun[\refreshGui].value;
    };

    ~sun[\cleanup] = { |quitServer=false|
        if(~sun.isNil) { ^nil };
        if(~sun[\isCleaningUp]) { ^nil };

        ~sun[\isCleaningUp] = true;
        ~sun[\guiMonitorActive] = false;

        if(MIDIdef(\sunBetaNoteOnV66).notNil) { MIDIdef(\sunBetaNoteOnV66).free; };
        if(MIDIdef(\sunBetaNoteOffV66).notNil) { MIDIdef(\sunBetaNoteOffV66).free; };

        if(~sun[\levelOsc].notNil) {
            ~sun[\levelOsc].free;
            ~sun[\levelOsc] = nil;
        };

        if(~sun[\arpTask].notNil) {
            ~sun[\arpTask].stop;
            ~sun[\arpTask] = nil;
        };

        ~sun[\heldNotes].clear;
        ~sun[\noteVelocities].clear;

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

        if(~sun[\monitorBus].notNil) {
            ~sun[\monitorBus].free;
            ~sun[\monitorBus] = nil;
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
        Rect(80, 60, 980, 540)
    ).front;

    ~sun[\window].background = Color(0.10, 0.10, 0.12);

    StaticText(~sun[\window], Rect(20, 14, 560, 28))
        .string_("Sun Arpeggios — Performance Interface")
        .font_(Font("Arial", 18, true))
        .stringColor_(Color.white);

    ~sun[\statusPanel] = makePanel.(~sun[\window], 20, 56, 940, 86, "System Status");
    ~sun[\instrumentPanel] = makePanel.(~sun[\window], 20, 156, 300, 170, "Instrument");
    ~sun[\performancePanel] = makePanel.(~sun[\window], 340, 156, 300, 310, "Performance Parameters");
    ~sun[\monitorPanel] = makePanel.(~sun[\window], 660, 156, 300, 210, "Signal Monitor");

    makeLabel.(~sun[\statusPanel], 14, 34, 120, 18, "MIDI Detection");

    ~sun[\views][\midiStatus] = StaticText(~sun[\statusPanel], Rect(14, 56, 760, 18))
        .string_("Initializing MIDI...")
        .stringColor_(Color(0.82, 0.92, 1.0))
        .font_(Font("Arial", 10));

    ~sun[\views][\resetBtn] = Button(~sun[\statusPanel], Rect(810, 14, 110, 28))
        .states_([["Reset", Color.white, Color(0.40, 0.25, 0.25)]])
        .action_({
            ~sun[\resetControls].value;
        });

    makeLabel.(~sun[\instrumentPanel], 14, 38, 170, 18, "Global Instrument");

    ~sun[\views][\instrumentPopup] = PopUpMenu(~sun[\instrumentPanel], Rect(14, 60, 276, 24))
        .items_(~sun[\instrumentNames])
        .background_(Color(0.20, 0.20, 0.24))
        .stringColor_(Color.white)
        .action_({ |menu|
            ~sun[\applyInstrumentSelection].value(menu.value);
        });

    makeSliderControl.(~sun[\performancePanel], \highNoteCeiling, "High Note Ceiling", 38, 84, 108, true);
    makeSliderControl.(~sun[\performancePanel], \arpRate, "Arp Rate", 96, 0.05, 0.22, false);
    makeSliderControl.(~sun[\performancePanel], \dynamicScale, "Global Dynamics", 154, 0.4, 1.7, false);
    makeSliderControl.(~sun[\performancePanel], \tailAmount, "Tail / Staccato", 212, 0.0, 1.0, false);
    makeSliderControl.(~sun[\performancePanel], \reverbMix, "Reverb Mix", 270, 0.0, 1.0, false);

    makeLabel.(~sun[\monitorPanel], 14, 38, 100, 18, "Level");

    ~sun[\views][\levelMeter] = LevelIndicator(~sun[\monitorPanel], Rect(14, 60, 272, 20))
        .warning_(0.65)
        .critical_(0.85)
        .drawsPeak_(true)
        .numTicks_(12)
        .background_(Color(0.16, 0.16, 0.18))
        .value_(0);

    makeLabel.(~sun[\monitorPanel], 14, 98, 130, 18, "Estimated Frequency");

    ~sun[\views][\freqText] = StaticText(~sun[\monitorPanel], Rect(14, 120, 272, 18))
        .string_("0.0 Hz")
        .stringColor_(Color(0.82, 0.92, 1.0))
        .font_(Font("Arial", 11));

    makeLabel.(~sun[\monitorPanel], 14, 154, 130, 18, "Current Instrument");

    ~sun[\views][\instrumentStatus] = StaticText(~sun[\monitorPanel], Rect(14, 176, 272, 18))
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

    ("Sun Arpeggios " ++ ~sun[\version] ++ " ready.").postln;
};
)