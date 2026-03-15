(
s.waitForBoot {

    ~sun = ();
    ~sun.activeNotes = IdentityDictionary.new;
    ~sun.heldNotes = IdentitySet.new;
    ~sun.lowHighSplit = 60;
    ~sun.reverbBus = Bus.audio(s, 2);
    ~sun.sourceGroup = Group.head(s);
    ~sun.fxGroup = Group.after(~sun.sourceGroup);
    ~sun.arpRoutine = nil;
    ~sun.arpStep = 0;
    ~sun.arpRate = 0.14;

    SynthDef(\sunMasterReverb, {
        |inBus=0, out=0, mix=0.28, room=0.85, damp=0.45|
        var dry, wet, sig;
        dry = In.ar(inBus, 2);
        wet = FreeVerb.ar(dry, mix, room, damp);
        sig = Limiter.ar(wet, 0.95);
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

    SynthDef(\sunHighVoice, {
        |out=0, freq=440, amp=0.08, gate=1, attack=0.0001, release=0.20, hpf=1400|
        var env, tone, air, sig;

        env = Env.asr(attack, 1, release).kr(2, gate);

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

    MIDIClient.init;
    MIDIIn.connectAll;
    MIDIdef.freeAll;

    "Connected MIDI sources:".postln;
    MIDIClient.sources.do { |src, i|
        ("Source " ++ i ++ ": " ++ src.device ++ " | " ++ src.name).postln;
    };

    ~sun.startArp = {
        if(~sun.arpRoutine.notNil) {
            ~sun.arpRoutine.stop;
            ~sun.arpRoutine = nil;
        };

        ~sun.arpRoutine = Routine({
            var notes, midiNote, freq, amp, hpf;

            loop {
                notes = ~sun.heldNotes.asArray.select { |n| n >= ~sun.lowHighSplit }.sort;

                if(notes.size > 0) {
                    midiNote = notes.wrapAt(~sun.arpStep);

                    freq = midiNote.midicps;
                    amp = 100.linlin(1, 127, 0.015, 0.09);
                    amp = amp.max(0.015).min(0.09);

                    hpf = midiNote.linexp(~sun.lowHighSplit, 108, 900, 4000);
                    hpf = hpf.max(900).min(4000);

                    Synth(\sunHighVoice, [
                        \out, ~sun.reverbBus,
                        \freq, freq,
                        \amp, amp,
                        \attack, 0.0001,
                        \release, 0.12,
                        \hpf, hpf
                    ], ~sun.sourceGroup);

                    if(notes.size > 1) {
                        freq = (midiNote + 12).midicps;
                        hpf = (midiNote + 12).linexp(~sun.lowHighSplit, 108, 1200, 5000);
                        hpf = hpf.max(1200).min(5000);

                        Synth(\sunHighVoice, [
                            \out, ~sun.reverbBus,
                            \freq, freq,
                            \amp, 0.045,
                            \attack, 0.0001,
                            \release, 0.09,
                            \hpf, hpf
                        ], ~sun.sourceGroup);
                    };

                    ~sun.arpStep = ~sun.arpStep + 1;
                };

                ~sun.arpRate.wait;
            }
        }).play(SystemClock);
    };

    ~sun.stopArp = {
        if(~sun.heldNotes.select({ |n| n >= ~sun.lowHighSplit }).isEmpty) {
            if(~sun.arpRoutine.notNil) {
                ~sun.arpRoutine.stop;
                ~sun.arpRoutine = nil;
                ~sun.arpStep = 0;
            };
        };
    };

    MIDIdef.noteOn(\sunLiveSplitNoteOn, { |vel, note, chan, src|
        var freq, synth, amp, attack, release, cutoff;

        ~sun.heldNotes.add(note);

        if(note < ~sun.lowHighSplit) {
            if(~sun.activeNotes[note].notNil) {
                ~sun.activeNotes[note].set(\gate, 0);
                ~sun.activeNotes.removeAt(note);
            };

            freq = note.midicps;
            amp = vel.linlin(1, 127, 0.04, 0.22);
            amp = amp.max(0.04).min(0.22);

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
            ~sun.startArp.();
        };

        ("NOTE ON | " ++ note ++ " vel: " ++ vel).postln;
    });

    MIDIdef.noteOff(\sunLiveSplitNoteOff, { |vel, note, chan, src|
        var synth;

        ~sun.heldNotes.remove(note);

        synth = ~sun.activeNotes[note];
        if(synth.notNil) {
            synth.set(\gate, 0);
            ~sun.activeNotes.removeAt(note);
        };

        ~sun.stopArp.();

        ("NOTE OFF | " ++ note).postln;
    });

    MIDIdef.cc(\sunArpRateCC, { |val|
        ~sun.arpRate = val.linlin(0, 127, 0.04, 0.35);
        ("Arp rate: " ++ ~sun.arpRate.round(0.01)).postln;
    }, 22);

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

    "Live split arp mode ready.".postln;
    "Low notes = sustained bass/organ.".postln;
    "High notes = arpeggiated voice.".postln;
    "Velocity affects low-note amplitude and arp accent.".postln;
};
)



(
MIDIdef.freeAll;

if(~sun.notNil) {
    if(~sun.activeNotes.notNil) {
        ~sun.activeNotes.keysValuesDo { |note, synth|
            if(synth.notNil) { synth.set(\gate, 0) };
        };
    };

    if(~sun.reverbSynth.notNil) { ~sun.reverbSynth.free };
    if(~sun.reverbBus.notNil) { ~sun.reverbBus.free };
    if(~sun.sourceGroup.notNil) { ~sun.sourceGroup.free };
    if(~sun.fxGroup.notNil) { ~sun.fxGroup.free };

    ~sun = nil;
};

"Cleaned previous state.".postln;
)