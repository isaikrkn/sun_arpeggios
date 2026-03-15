// Sun Arpeggios GUI App - Clean V4
// Single-file SuperCollider GUI application.
// Comments are intentionally in English.

(
MIDIdef.freeAll;
OSCdef.freeAll;

if(~sun.notNil) {
    if(~sun[\arpRoutine].notNil) {
        ~sun[\arpRoutine].stop;
        ~sun[\arpRoutine] = nil;
    };

    if(~sun[\meterUpdater].notNil) {
        ~sun[\meterUpdater].stop;
        ~sun[\meterUpdater] = nil;
    };

    if(~sun[\midiNoteOnDef].notNil) { ~sun[\midiNoteOnDef].free };
    if(~sun[\midiNoteOffDef].notNil) { ~sun[\midiNoteOffDef].free };
    if(~sun[\oscLevelDef].notNil) { ~sun[\oscLevelDef].free };

    if(~sun[\activeNotes].notNil) {
        ~sun[\activeNotes].keysValuesDo { |note, synth|
            if(synth.notNil) { synth.set(\gate, 0) };
        };
    };

    if(~sun[\monitorSynth].notNil) { ~sun[\monitorSynth].free };
    if(~sun[\masterFxSynth].notNil) { ~sun[\masterFxSynth].free };
    if(~sun[\sourceBus].notNil) { ~sun[\sourceBus].free };
    if(~sun[\sourceGroup].notNil) { ~sun[\sourceGroup].freeAll; ~sun[\sourceGroup].free };
    if(~sun[\fxGroup].notNil) { ~sun[\fxGroup].freeAll; ~sun[\fxGroup].free };
    if(~sun[\window].notNil) { ~sun[\window].close };

    ~sun = nil;
};

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

    ~sun[\dynamicScale] = 1.0;
    ~sun[\lowDynamicScale] = 1.0;
    ~sun[\highDynamicScale] = 1.0;
    ~sun[\highFadeOut] = 3.0;
    ~sun[\highBrightnessScale] = 1.0;
    ~sun[\extraVoiceProb] = 0.18;

    ~sun[\reverbMix] = 0.24;
    ~sun[\reverbRoom] = 0.82;
    ~sun[\reverbDamp] = 0.52;

    ~sun[\flangerMix] = 0.0;
    ~sun[\flangerRate] = 0.14;
    ~sun[\flangerDepth] = 0.0025;
    ~sun[\flangerFeedback] = 0.18;

    ~sun[\selectedLowInstrument] = \sunLowDroneLP;
    ~sun[\selectedHighInstrument] = \sunHighDroneHP;

    ~sun[\lowInstrumentNames] = ["Drone LP", "Organ Bass", "Contrabass"];
    ~sun[\lowInstrumentKeys] = [\sunLowDroneLP, \sunLowOrganBass, \sunLowContraBass];

    ~sun[\highInstrumentNames] = ["Drone HP", "Bright Arp", "Glass Arp"];
    ~sun[\highInstrumentKeys] = [\sunHighDroneHP, \sunHighBrightArp, \sunHighGlassArp];

    ~sun[\lastFreq] = 0.0;
    ~sun[\lastLevel] = 0.0;
    ~sun[\midiStatusText] = "No MIDI sources detected yet.";

    ~sun[\sourceBus] = Bus.audio(s, 2);
    ~sun[\sourceGroup] = Group.head(s);
    ~sun[\fxGroup] = Group.after(~sun[\sourceGroup]);

    ~sun[\window] = nil;
    ~sun[\masterFxSynth] = nil;
    ~sun[\monitorSynth] = nil;
    ~sun[\meterUpdater] = nil;
    ~sun[\midiNoteOnDef] = nil;
    ~sun[\midiNoteOffDef] = nil;
    ~sun[\oscLevelDef] = nil;
    ~sun[\views] = IdentityDictionary.new;
    ~sun[\labels] = IdentityDictionary.new;

    // --------------------------------------------------------
    // SynthDefs based on original drone / drone1 logic
    // --------------------------------------------------------

    SynthDef(\sunMasterFX, {
        |inBus=0, out=0, reverbMix=0.24, reverbRoom=0.82, reverbDamp=0.52,
        flangerMix=0.0, flangerRate=0.14, flangerDepth=0.0025, flangerFeedback=0.18|
        var dry, mod, delayed, feedbackSig, flanged, reverbed, sig;

        dry = In.ar(inBus, 2);
        feedbackSig = LocalIn.ar(2);
        mod = SinOsc.kr(flangerRate, 0, flangerDepth, flangerDepth + 0.001);
        delayed = DelayC.ar(dry + (feedbackSig * flangerFeedback), 0.03, mod);
        LocalOut.ar(delayed);
        flanged = (dry + delayed) * 0.5;
        reverbed = FreeVerb.ar(dry, 1.0, reverbRoom, reverbDamp);

        sig = dry;
        sig = XFade2.ar(sig, flanged, flangerMix.linlin(0, 1, -1, 1));
        sig = XFade2.ar(sig, reverbed, reverbMix.linlin(0, 1, -1, 1));
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
        env = Env.asr(attack, 1, release).kr(2, gate);
        snd = snd * amp * env;
        snd = RLPF.ar(snd, ffreq, rq);
        snd = BLowShelf.ar(snd, 130, 0.8, 4);
        snd = LeakDC.ar(snd);
        snd = tanh(snd * 1.15);
        Out.ar(out, snd);
    }).add;

    SynthDef(\sunLowOrganBass, {
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
        sig = tanh(sig * 1.35);
        sig = Pan2.ar(sig * env * amp, 0);
        Out.ar(out, sig);
    }).add;

    SynthDef(\sunLowContraBass, {
        |out=0, freq=110, amp=0.15, gate=1, attack=0.1, release=2.0, cutoff=850|
        var env, bow, body, sub, sig;
        env = Env.asr(attack, 1, release).kr(2, gate);
        sub = SinOsc.ar(freq * 0.5, 0, 0.20);
        bow = LPF.ar(WhiteNoise.ar(0.04), cutoff * 0.4) * Env.perc(0.003, 0.08).kr;
        body = Mix([
            VarSaw.ar(freq * 0.999, 0, 0.35, 0.12),
            VarSaw.ar(freq * 1.001, 0, 0.42, 0.12),
            SinOsc.ar(freq, 0, 0.11)
        ]);
        sig = sub + body + bow;
        sig = LPF.ar(sig, cutoff);
        sig = BPeakEQ.ar(sig, (freq * 2).clip(80, 900), 0.6, 2.2);
        sig = BLowShelf.ar(sig, 110, 0.7, 5);
        sig = LeakDC.ar(sig);
        sig = tanh(sig * 1.25);
        sig = Pan2.ar(sig * env * amp, 0);
        Out.ar(out, sig);
    }).add;

    SynthDef(\sunHighDroneHP, {
        |out=0, freq=440, amp=0.05, attack=0.0001, fadeOut=3.0, hpf=1400, lpf=7000, bright=0.6|
        var snd, env, ffreq, rq;
        snd = { Gendy1.ar(1, 1, 1, 1, freq * 0.99, freq * 1.01) } ! 6;
        snd = Splay.ar(snd);
        ffreq = LFNoise2.kr(2.1).exprange(hpf.max(300), (hpf * 2.3).clip(400, 9000));
        rq = LFNoise2.kr(3.2).range(0.25, 0.8);
        env = Env.perc(attack, fadeOut, 1, curve: -4).kr(doneAction: 2);
        snd = snd * amp * env;
        snd = RHPF.ar(snd, ffreq, rq);
        snd = LPF.ar(snd, lpf);
        snd = BPeakEQ.ar(snd, freq.clip(600, 3800), 0.45, bright);
        snd = LeakDC.ar(snd);
        snd = tanh(snd * 0.95);
        Out.ar(out, snd);
    }).add;

    SynthDef(\sunHighBrightArp, {
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

    SynthDef(\sunHighGlassArp, {
        |out=0, freq=440, amp=0.05, attack=0.0001, fadeOut=2.5, hpf=1400, lpf=6500, bright=0.6|
        var env, tone, shimmer, sig, safeFreq;
        safeFreq = freq.clip(120, 5000);
        env = Env.perc(attack, fadeOut, 1, curve: -5).kr(doneAction: 2);
        tone = Mix([
            SinOsc.ar(safeFreq, 0, 0.18),
            PMOsc.ar(safeFreq, safeFreq * 1.5, 2.2, 0, 0.10),
            SinOsc.ar(safeFreq * 2.01, 0, 0.05)
        ]);
        shimmer = HPF.ar(WhiteNoise.ar(0.008), hpf * 1.2) * Env.perc(0.001, 0.05).kr;
        sig = tone + shimmer;
        sig = HPF.ar(sig, hpf);
        sig = LPF.ar(sig, lpf);
        sig = BPeakEQ.ar(sig, safeFreq.clip(800, 4200), 0.5, bright * 0.8);
        sig = LeakDC.ar(sig);
        sig = tanh(sig * 0.78);
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

    ~sun[\masterFxSynth] = Synth.tail(~sun[\fxGroup], \sunMasterFX, [
        \inBus, ~sun[\sourceBus],
        \out, 0,
        \reverbMix, ~sun[\reverbMix],
        \reverbRoom, ~sun[\reverbRoom],
        \reverbDamp, ~sun[\reverbDamp],
        \flangerMix, ~sun[\flangerMix],
        \flangerRate, ~sun[\flangerRate],
        \flangerDepth, ~sun[\flangerDepth],
        \flangerFeedback, ~sun[\flangerFeedback]
    ]);

    ~sun[\monitorSynth] = Synth.tail(~sun[\fxGroup], \sunOutputMonitor, [\inBus, 0]);

    ~sun[\oscLevelDef] = OSCdef(\sunLevelWatcher, { |msg|
        if(msg.size > 3) {
            ~sun[\lastLevel] = msg[3].asFloat;
        };
    }, '/sunLevel');

    // --------------------------------------------------------
    // Helpers
    // --------------------------------------------------------

    ~sun[\updateFx] = { |state|
        if(state[\masterFxSynth].notNil) {
            state[\masterFxSynth].set(
                \reverbMix, state[\reverbMix],
                \reverbRoom, state[\reverbRoom],
                \reverbDamp, state[\reverbDamp],
                \flangerMix, state[\flangerMix],
                \flangerRate, state[\flangerRate],
                \flangerDepth, state[\flangerDepth],
                \flangerFeedback, state[\flangerFeedback]
            );
        };
    };

    ~sun[\playLowVoice] = { |state, freq, amp, attack, release, cutoff|
        ^Synth(state[\selectedLowInstrument], [
            \out, state[\sourceBus],
            \freq, freq,
            \amp, amp,
            \attack, attack,
            \release, release,
            \cutoff, cutoff
        ], state[\sourceGroup]);
    };

    ~sun[\playHighVoice] = { |state, midiNote, vel, fadeScale=1.0|
        var amp, hpf, lpf, bright, fadeOut, ceilingRef, freq;
        ceilingRef = state[\highNoteCeiling].max(state[\lowHighSplit] + 1);
        freq = midiNote.midicps;
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
        fadeOut = (fadeOut * fadeScale).max(0.35).min(5.0);
        state[\lastFreq] = freq;
        Synth(state[\selectedHighInstrument], [
            \out, state[\sourceBus],
            \freq, freq,
            \amp, amp,
            \attack, 0.0001,
            \fadeOut, fadeOut,
            \hpf, hpf,
            \lpf, lpf,
            \bright, bright
        ], state[\sourceGroup]);
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
        if(state[\arpRoutine].isNil) {
            state[\arpRoutine] = Routine({
                var notes, baseNote, octaveShift, midiNote, vel, extraVoice;
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
                        state[\playHighVoice].value(state, midiNote, vel, 1.0);
                        extraVoice = state[\extraVoiceProb].coin and: { notes.size > 1 };
                        if(extraVoice) {
                            baseNote = notes.choose;
                            octaveShift = if(baseNote >= 79) {
                                [0, 12].wchoose([0.7, 0.3]);
                            } {
                                [12, 24].wchoose([0.75, 0.25]);
                            };
                            midiNote = (baseNote + octaveShift).min(state[\highNoteCeiling]);
                            state[\playHighVoice].value(state, midiNote, vel, 0.75);
                        };
                    };
                    state[\arpRate].wait;
                }
            }).play(SystemClock);
        };
    };

    ~sun[\processNoteOn] = { |state, vel, note|
        var freq, synth, amp, attack, release, cutoff, splitTop;
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
            amp = vel.linexp(1, 127, 0.025, 0.22);
            amp = amp * state[\lowDynamicScale] * state[\dynamicScale];
            amp = amp.max(0.015).min(0.30);
            attack = vel.linlin(1, 127, 0.18, 0.05);
            attack = attack * note.linlin(24, splitTop, 1.1, 0.9);
            attack = attack.max(0.04).min(0.22);
            release = vel.linlin(1, 127, 3.2, 1.6);
            release = release.max(1.2).min(3.5);
            cutoff = note.linexp(24, splitTop, 220, 900);
            cutoff = cutoff * vel.linlin(1, 127, 0.55, 1.35);
            cutoff = cutoff.max(220).min(1500);
            synth = state[\playLowVoice].value(state, freq, amp, attack, release, cutoff);
            state[\activeNotes].put(note, synth);
        } {
            state[\heldHigh].add(note);
            state[\highVelocities].put(note, vel);
            state[\startArp].value(state);
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
        state[\lowHighSplit] = 60;
        state[\highNoteCeiling] = 96;
        state[\arpRate] = 0.095367432;
        state[\dynamicScale] = 1.0;
        state[\lowDynamicScale] = 1.0;
        state[\highDynamicScale] = 1.0;
        state[\highFadeOut] = 3.0;
        state[\highBrightnessScale] = 1.0;
        state[\extraVoiceProb] = 0.18;
        state[\reverbMix] = 0.24;
        state[\reverbRoom] = 0.82;
        state[\reverbDamp] = 0.52;
        state[\flangerMix] = 0.0;
        state[\flangerRate] = 0.14;
        state[\flangerDepth] = 0.0025;
        state[\flangerFeedback] = 0.18;
        state[\selectedLowInstrument] = \sunLowDroneLP;
        state[\selectedHighInstrument] = \sunHighDroneHP;
        state[\updateFx].value(state);
        if(state[\refreshGui].notNil) { state[\refreshGui].value };
    };

    // --------------------------------------------------------
    // GUI helpers
    // --------------------------------------------------------

    ~sun[\makePanel] = { |parent, x, y, w, h, title|
        var panel;
        panel = CompositeView(parent, Rect(x, y, w, h));
        panel.background_(Color(0.14, 0.14, 0.17));
        StaticText(panel, Rect(12, 8, w - 24, 22))
            .string_(title)
            .stringColor_(Color.white)
            .font_(Font("Arial", 12, true));
        ^panel;
    };

    ~sun[\makeLabel] = { |parent, x, y, w, h, text|
        StaticText(parent, Rect(x, y, w, h))
            .string_(text)
            .stringColor_(Color.white)
            .font_(Font("Arial", 10));
    };

    ~sun[\makeValue] = { |parent, x, y, w, h, text=""|
        StaticText(parent, Rect(x, y, w, h))
            .string_(text)
            .align_(\right)
            .stringColor_(Color(0.82, 0.92, 1.0))
            .font_(Font("Arial", 10));
    };

    ~sun[\makeSliderControl] = { |panel, key, title, lo, hi, y, isInt=false|
        var valueLabel, slider;
        ~sun[\makeLabel].(panel, 14, y, 150, 18, title);
        valueLabel = ~sun[\makeValue].(panel, 220, y, 70, 18, "");
        slider = Slider(panel, Rect(14, y + 20, 276, 20))
            .background_(Color(0.18, 0.18, 0.22))
            .knobColor_(Color(0.30, 0.60, 0.95))
            .action_({ |sl|
                var mapped;
                mapped = sl.value.linlin(0, 1, lo, hi);
                if(isInt) { mapped = mapped.round(1).asInteger };
                ~sun[key] = mapped;
                if([
                    \reverbMix, \reverbRoom, \reverbDamp,
                    \flangerMix, \flangerRate, \flangerDepth, \flangerFeedback
                ].includes(key)) {
                    ~sun[\updateFx].value(~sun);
                };
                valueLabel.string = if(isInt) { mapped.asString } { mapped.round(0.001).asString };
            });
        ~sun[\views][key] = slider;
        ~sun[\labels][key] = valueLabel;
    };

    // --------------------------------------------------------
    // GUI layout
    // --------------------------------------------------------

    ~sun[\window] = Window("Sun Arpeggios", Rect(70, 50, 980, 690)).front;
    ~sun[\window].background_(Color(0.10, 0.10, 0.12));

    StaticText(~sun[\window], Rect(20, 14, 420, 28))
        .string_("Sun Arpeggios — Performance Interface")
        .font_(Font("Arial", 18, true))
        .stringColor_(Color.white);

    ~sun[\statusPanel] = ~sun[\makePanel].(~sun[\window], 20, 56, 940, 86, "System Status");
    ~sun[\instrumentPanel] = ~sun[\makePanel].(~sun[\window], 20, 156, 300, 194, "Split and Instruments");
    ~sun[\performancePanel] = ~sun[\makePanel].(~sun[\window], 340, 156, 300, 504, "Performance Parameters");
    ~sun[\fxPanel] = ~sun[\makePanel].(~sun[\window], 660, 156, 300, 300, "FX Chain");
    ~sun[\monitorPanel] = ~sun[\makePanel].(~sun[\window], 660, 470, 300, 190, "Signal Monitor");

    ~sun[\makeLabel].(~sun[\statusPanel], 14, 34, 120, 18, "MIDI Detection");
    ~sun[\views][\midiStatus] = StaticText(~sun[\statusPanel], Rect(14, 56, 910, 18))
        .string_("Initializing MIDI...")
        .stringColor_(Color(0.82, 0.92, 1.0))
        .font_(Font("Arial", 10));

    ~sun[\views][\resetBtn] = Button(~sun[\statusPanel], Rect(810, 14, 110, 28))
        .states_([["Reset", Color.white, Color(0.40, 0.25, 0.25)]])
        .action_({ ~sun[\resetControls].value(~sun) });

    ~sun[\makeLabel].(~sun[\instrumentPanel], 14, 38, 150, 18, "Split Point");
    ~sun[\labels][\lowHighSplit] = ~sun[\makeValue].(~sun[\instrumentPanel], 220, 38, 70, 18, "");
    ~sun[\views][\lowHighSplit] = Slider(~sun[\instrumentPanel], Rect(14, 60, 276, 20))
        .background_(Color(0.18, 0.18, 0.22))
        .knobColor_(Color(0.30, 0.60, 0.95))
        .action_({ |sl|
            ~sun[\lowHighSplit] = sl.value.linlin(0, 1, 48, 72).round(1).asInteger;
            ~sun[\labels][\lowHighSplit].string = ~sun[\lowHighSplit].asString;
        });

    ~sun[\makeLabel].(~sun[\instrumentPanel], 14, 98, 170, 18, "Low Instrument");
    ~sun[\views][\lowInstrumentPopup] = PopUpMenu(~sun[\instrumentPanel], Rect(14, 120, 276, 24))
        .items_(~sun[\lowInstrumentNames])
        .background_(Color(0.20, 0.20, 0.24))
        .stringColor_(Color.white)
        .action_({ |menu|
            ~sun[\selectedLowInstrument] = ~sun[\lowInstrumentKeys][menu.value];
        });

    ~sun[\makeLabel].(~sun[\instrumentPanel], 14, 156, 170, 18, "High Instrument");
    ~sun[\views][\highInstrumentPopup] = PopUpMenu(~sun[\instrumentPanel], Rect(14, 178, 276, 24))
        .items_(~sun[\highInstrumentNames])
        .background_(Color(0.20, 0.20, 0.24))
        .stringColor_(Color.white)
        .action_({ |menu|
            ~sun[\selectedHighInstrument] = ~sun[\highInstrumentKeys][menu.value];
        });

    ~sun[\makeSliderControl].(~sun[\performancePanel], \highNoteCeiling, "High Note Ceiling", 84, 108, 38, true);
    ~sun[\makeSliderControl].(~sun[\performancePanel], \arpRate, "Arp Rate", 0.05, 0.22, 96, false);
    ~sun[\makeSliderControl].(~sun[\performancePanel], \dynamicScale, "Global Dynamics", 0.4, 1.7, 154, false);
    ~sun[\makeSliderControl].(~sun[\performancePanel], \lowDynamicScale, "Low Dynamics", 0.5, 1.6, 212, false);
    ~sun[\makeSliderControl].(~sun[\performancePanel], \highDynamicScale, "High Dynamics", 0.4, 1.5, 270, false);
    ~sun[\makeSliderControl].(~sun[\performancePanel], \highFadeOut, "High Fade Out", 0.6, 4.5, 328, false);
    ~sun[\makeSliderControl].(~sun[\performancePanel], \highBrightnessScale, "High Brightness", 0.3, 1.6, 386, false);
    ~sun[\makeSliderControl].(~sun[\performancePanel], \extraVoiceProb, "Extra Voice Probability", 0.0, 0.40, 444, false);

    ~sun[\makeSliderControl].(~sun[\fxPanel], \reverbMix, "Reverb Mix", 0.0, 0.55, 38, false);
    ~sun[\makeSliderControl].(~sun[\fxPanel], \reverbRoom, "Reverb Room", 0.2, 1.0, 96, false);
    ~sun[\makeSliderControl].(~sun[\fxPanel], \reverbDamp, "Reverb Damp", 0.15, 0.85, 154, false);
    ~sun[\makeSliderControl].(~sun[\fxPanel], \flangerMix, "Flanger Mix", 0.0, 0.9, 212, false);
    ~sun[\makeSliderControl].(~sun[\fxPanel], \flangerRate, "Flanger Rate", 0.03, 1.2, 270, false);
    ~sun[\makeSliderControl].(~sun[\fxPanel], \flangerDepth, "Flanger Depth", 0.0004, 0.008, 328, false);
    ~sun[\makeSliderControl].(~sun[\fxPanel], \flangerFeedback, "Flanger Feedback", 0.0, 0.85, 386, false);

    ~sun[\makeLabel].(~sun[\monitorPanel], 14, 38, 90, 18, "Level");
    ~sun[\views][\levelMeter] = LevelIndicator(~sun[\monitorPanel], Rect(14, 60, 272, 20))
        .warning_(0.65)
        .critical_(0.85)
        .drawsPeak_(true)
        .numTicks_(12)
        .background_(Color(0.16, 0.16, 0.18))
        .value_(0);

    ~sun[\makeLabel].(~sun[\monitorPanel], 14, 96, 120, 18, "Estimated Frequency");
    ~sun[\views][\freqText] = StaticText(~sun[\monitorPanel], Rect(14, 118, 272, 18))
        .string_("0.0 Hz")
        .stringColor_(Color(0.82, 0.92, 1.0))
        .font_(Font("Arial", 11));

    ~sun[\makeLabel].(~sun[\monitorPanel], 14, 146, 200, 18, "Low / High Instruments");
    ~sun[\views][\instrumentStatus] = StaticText(~sun[\monitorPanel], Rect(14, 168, 272, 18))
        .string_("")
        .stringColor_(Color(0.82, 0.92, 1.0))
        .font_(Font("Arial", 10));

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
            [\highBrightnessScale, 0.3, 1.6, false],
            [\extraVoiceProb, 0.0, 0.40, false],
            [\reverbMix, 0.0, 0.55, false],
            [\reverbRoom, 0.2, 1.0, false],
            [\reverbDamp, 0.15, 0.85, false],
            [\flangerMix, 0.0, 0.9, false],
            [\flangerRate, 0.03, 1.2, false],
            [\flangerDepth, 0.0004, 0.008, false],
            [\flangerFeedback, 0.0, 0.85, false]
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

        if(~sun[\views][\lowHighSplit].notNil) {
            ~sun[\views][\lowHighSplit].value = ~sun[\lowHighSplit].linlin(48, 72, 0, 1).clip(0, 1);
        };
        if(~sun[\labels][\lowHighSplit].notNil) {
            ~sun[\labels][\lowHighSplit].string = ~sun[\lowHighSplit].asString;
        };

        if(~sun[\views][\lowInstrumentPopup].notNil) {
            ~sun[\views][\lowInstrumentPopup].value = ~sun[\lowInstrumentKeys].indexOf(~sun[\selectedLowInstrument]).max(0);
        };
        if(~sun[\views][\highInstrumentPopup].notNil) {
            ~sun[\views][\highInstrumentPopup].value = ~sun[\highInstrumentKeys].indexOf(~sun[\selectedHighInstrument]).max(0);
        };

        if(~sun[\views][\instrumentStatus].notNil) {
            ~sun[\views][\instrumentStatus].string =
            ("Low: " ++ ~sun[\lowInstrumentNames][~sun[\lowInstrumentKeys].indexOf(~sun[\selectedLowInstrument]).max(0)])
            ++ "   |   " ++
            ("High: " ++ ~sun[\highInstrumentNames][~sun[\highInstrumentKeys].indexOf(~sun[\selectedHighInstrument]).max(0)]);
        };

        ~sun[\updateFx].value(~sun);
    };

    // --------------------------------------------------------
    // MIDI detection and connection
    // --------------------------------------------------------

    MIDIClient.init;
    MIDIIn.connectAll;

    if(MIDIClient.sources.isEmpty) {
        ~sun[\midiStatusText] = "No MIDI sources detected.";
    } {
        ~sun[\midiStatusText] = "Detected MIDI sources: " ++ MIDIClient.sources.collect { |src|
            src.device ++ " | " ++ src.name
        }.join("    ||    ");
    };

    ~sun[\views][\midiStatus].string = ~sun[\midiStatusText];
    ~sun[\connectMidi].value(~sun);
    ~sun[\refreshGui].value;

    // --------------------------------------------------------
    // Meter updater
    // --------------------------------------------------------

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
                    if(~sun[\views][\instrumentStatus].notNil) {
                        ~sun[\views][\instrumentStatus].string =
                        ("Low: " ++ ~sun[\lowInstrumentNames][~sun[\lowInstrumentKeys].indexOf(~sun[\selectedLowInstrument]).max(0)])
                        ++ "   |   " ++
                        ("High: " ++ ~sun[\highInstrumentNames][~sun[\highInstrumentKeys].indexOf(~sun[\selectedHighInstrument]).max(0)]);
                    };
                };
            }.defer;
            0.08.wait;
        }
    }).play(AppClock);

    // --------------------------------------------------------
    // Window close cleanup
    // --------------------------------------------------------

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
        if(~sun[\masterFxSynth].notNil) { ~sun[\masterFxSynth].free };
        if(~sun[\sourceBus].notNil) { ~sun[\sourceBus].free };
        if(~sun[\sourceGroup].notNil) { ~sun[\sourceGroup].freeAll; ~sun[\sourceGroup].free };
        if(~sun[\fxGroup].notNil) { ~sun[\fxGroup].freeAll; ~sun[\fxGroup].free };

        ~sun = nil;
    };

    "Sun Arpeggios GUI Clean V4 ready.".postln;
};
)
