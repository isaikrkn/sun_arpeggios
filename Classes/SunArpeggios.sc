SunArpeggios {
    var <server;
    var <sourceGroup;
    var <fxGroup;
    var <reverbBus;
    var <reverbSynth;

    var <state;
    var <chordDefs;
    var <currentChord;
    var <players;
    var <heldNotes;

    *new { |server|
        ^super.new.init(server ? Server.default);
    }

    init { |inServer|
        server = inServer;
        players = List.new;
        heldNotes = IdentitySet.new;

        state = (
            root: 60,
            chordType: \minor,
            amp: 0.05,
            density: 1.0,
            attack: 0.08,
            release: 1.8,
            reverbMix: 0.28,
            room: 0.82,
            damp: 0.45
        );

        chordDefs = (
            major: [0, 4, 7],
            minor: [0, 3, 7],
            dim: [0, 3, 6],
            aug: [0, 4, 8],
            sus2: [0, 2, 7],
            sus4: [0, 5, 7],
            maj7: [0, 4, 7, 11],
            min7: [0, 3, 7, 10],
            dom7: [0, 4, 7, 10],
            add9: [0, 4, 7, 14],
            minAdd9: [0, 3, 7, 14],
            maj9: [0, 4, 7, 11, 14],
            min9: [0, 3, 7, 10, 14],
            dom9: [0, 4, 7, 10, 14],
            maj6: [0, 4, 7, 9],
            min6: [0, 3, 7, 9],
            min11: [0, 3, 7, 10, 14, 17],
            dom13: [0, 4, 7, 10, 14, 21]
        );

        currentChord = this.buildChord(state[\root], state[\chordType]);
        ^this
    }

    loadSynthDefs {
        SynthDef(\sunBassDrone, {
            |out=0, freq=110, amp=0.07, gate=1, attack=0.08, release=3.0, cutoff=500|
            var sig, env, sub;

            sub = SinOsc.ar(freq * 0.5, 0, 0.35);
            sig = Mix([
                Saw.ar(freq, 0.18),
                Pulse.ar(freq * 0.5, 0.45, 0.15),
                sub
            ]);

            sig = LPF.ar(sig, cutoff);
            sig = LeakDC.ar(sig);
            sig = tanh(sig * 1.4);

            env = Env.asr(attack, 1, release).ar(2, gate);
            Out.ar(out, Pan2.ar(sig * env * amp, 0));
        }).add;

        SynthDef(\sunWarmDrone, {
            |out=0, freq=440, amp=0.05, gate=1, attack=0.2, release=2.5, cutoff=1800, rq=0.25, detune=0.015|
            var osc1, osc2, osc3, noiseLayer, env, sig;

            osc1 = VarSaw.ar(freq * (1 - detune), 0, 0.45);
            osc2 = VarSaw.ar(freq * (1 + detune), 0, 0.52);
            osc3 = SinOsc.ar(freq * 0.5, 0, 0.25);

            noiseLayer = Gendy1.ar(1, 1, 1, 1, freq * 0.995, freq * 1.005, 0.12, 0.08);
            noiseLayer = LPF.ar(noiseLayer, cutoff * 0.7);

            sig = (osc1 + osc2 + osc3 + (noiseLayer * 0.18)) * 0.35;
            sig = RLPF.ar(sig, cutoff, rq);
            sig = LeakDC.ar(sig);
            sig = tanh(sig * 1.2);

            env = Env.asr(attack, 1, release).ar(2, gate);
            sig = Splay.ar([sig, DelayC.ar(sig, 0.03, 0.01)], 0.25);

            Out.ar(out, sig * env * amp);
        }).add;

        SynthDef(\sunShimmer, {
            |out=0, freq=440, amp=0.02, gate=1, attack=0.01, release=0.4, hpf=1200|
            var sig, env;

            sig = Mix([
                Pulse.ar(freq, 0.45, 0.18),
                SinOsc.ar(freq * 2, 0, 0.08),
                Gendy1.ar(1, 1, 1, 1, freq * 0.998, freq * 1.002, 0.04, 0.03) * 0.08
            ]);

            sig = HPF.ar(sig, hpf);
            sig = BPeakEQ.ar(sig, freq * 2, 0.6, 2);
            sig = tanh(sig * 1.1);

            env = Env.asr(attack, 1, release).ar(2, gate);
            Out.ar(out, Splay.ar(sig ! 2, 0.1) * env * amp);
        }).add;

        SynthDef(\sunSpace, {
            |inBus=0, out=0, mix=0.28, room=0.82, damp=0.45|
            var sig;
            sig = In.ar(inBus, 2);
            sig = FreeVerb.ar(sig, mix, room, damp);
            sig = Limiter.ar(sig, 0.9);
            Out.ar(out, sig);
        }).add;
    }

    setupAudio {
        server.sync;

        reverbBus = Bus.audio(server, 2);
        sourceGroup = Group.head(server);
        fxGroup = Group.after(sourceGroup);

        reverbSynth = Synth.tail(fxGroup, \sunSpace, [
            \inBus, reverbBus,
            \out, 0,
            \mix, state[\reverbMix],
            \room, state[\room],
            \damp, state[\damp]
        ]);
    }

    buildChord { |root=60, chordType=\minor|
        var intervals;
        intervals = chordDefs[chordType] ? chordDefs[\minor];
        ^intervals.collect { |interval| root + interval };
    }

    openVoicing { |notes|
        var sorted;
        sorted = notes.sort.copy;

        if(sorted.size >= 3) {
            sorted[1] = sorted[1] + 12;
        };

        if(sorted.size >= 5) {
            sorted[3] = sorted[3] + 12;
        };

        ^sorted.sort
    }

    splitChordRoles { |chord|
        var sorted;
        sorted = chord.sort;

        ^(
            bass: [sorted[0], sorted[0] + 12, sorted[2] ? sorted[0]],
            guide: [sorted[1] ? sorted[0], sorted[3] ? sorted[1] ? sorted[0]],
            color: sorted.drop(2)
        )
    }

    setChord { |root=60, chordType=\minor|
        state[\root] = root;
        state[\chordType] = chordType;
        currentChord = this.openVoicing(this.buildChord(root, chordType));
        ("New chord -> root: " ++ root ++ ", type: " ++ chordType ++ ", notes: " ++ currentChord).postln;
        ^currentChord
    }

    setAmp { |value|
        state[\amp] = value.clip(0.001, 0.5);
    }

    setDensity { |value|
        state[\density] = value.clip(0.1, 12.0);
    }

    setAttack { |value|
        state[\attack] = value.clip(0.001, 10.0);
    }

    setRelease { |value|
        state[\release] = value.clip(0.01, 20.0);
    }

    setReverbMix { |value|
        state[\reverbMix] = value.clip(0.0, 1.0);
        if(reverbSynth.notNil) {
            reverbSynth.set(\mix, state[\reverbMix]);
        };
    }

    setRoom { |value|
        state[\room] = value.clip(0.0, 1.0);
        if(reverbSynth.notNil) {
            reverbSynth.set(\room, state[\room]);
        };
    }

    setDamp { |value|
        state[\damp] = value.clip(0.0, 1.0);
        if(reverbSynth.notNil) {
            reverbSynth.set(\damp, state[\damp]);
        };
    }

    play {
        var roles;

        this.stop;
        roles = this.splitChordRoles(currentChord);

        players.add(
            Pbind(
                \instrument, \sunBassDrone,
                \group, sourceGroup,
                \dur, Pfunc { 6.0 / state[\density].max(0.1) },
                \midinote, Pfunc {
                    var r;
                    r = this.splitChordRoles(currentChord);
                    r[\bass].choose;
                },
                \freq, Pkey(\midinote).midicps,
                \amp, Pfunc { state[\amp] * 1.2 },
                \attack, Pfunc { state[\attack] + 0.04 },
                \release, Pfunc { state[\release] * 1.8 },
                \cutoff, Pexprand(180, 700),
                \out, reverbBus
            ).play
        );

        players.add(
            Pbind(
                \instrument, \sunWarmDrone,
                \group, sourceGroup,
                \dur, Pfunc { 1.8 / state[\density].max(0.1) },
                \midinote, Pfunc {
                    var r;
                    r = this.splitChordRoles(currentChord);
                    (r[\guide] ++ r[\color]).choose;
                },
                \freq, Pkey(\midinote).midicps,
                \amp, Pfunc { state[\amp] * 0.75 },
                \attack, Pfunc { state[\attack] + 0.08 },
                \release, Pfunc { state[\release] * 1.4 },
                \cutoff, Pexprand(600, 2600),
                \rq, Pwhite(0.18, 0.4),
                \detune, Pwhite(0.004, 0.02),
                \out, reverbBus
            ).play
        );

        players.add(
            Pbind(
                \instrument, \sunShimmer,
                \group, sourceGroup,
                \dur, Pfunc { 0.22 / state[\density].max(0.1) },
                \midinote, Pfunc {
                    var r;
                    r = this.splitChordRoles(currentChord);
                    (r[\color] ++ (r[\color] + 12) ++ (r[\guide] + 12)).choose;
                },
                \freq, Pkey(\midinote).midicps,
                \amp, Pfunc { state[\amp] * 0.18 },
                \attack, 0.01,
                \release, Pfunc { (state[\release] * 0.18).clip(0.04, 1.2) },
                \hpf, Pexprand(900, 4200),
                \out, reverbBus
            ).play
        );

        "SunArpeggios patterns started.".postln;
    }

    stop {
        if(players.notNil) {
            players.do { |player|
                if(player.notNil) { player.stop };
            };
        };
        players = List.new;
    }

    cleanup {
        this.stop;

        if(reverbSynth.notNil) { reverbSynth.free };
        if(reverbBus.notNil) { reverbBus.free };
        if(sourceGroup.notNil) { sourceGroup.free };
        if(fxGroup.notNil) { fxGroup.free };

        reverbSynth = nil;
        reverbBus = nil;
        sourceGroup = nil;
        fxGroup = nil;
    }

    setupMidi {
        MIDIClient.init;
        MIDIIn.connectAll;
        "MIDI initialized and all sources connected.".postln;
    }

    listMidiSources {
        MIDIClient.sources.do { |src, i|
            ("Source " ++ i ++ ": " ++ src.device ++ " | " ++ src.name).postln;
        };
    }

    clearMidiDefs {
        MIDIdef.freeAll;
    }

    setupRootNoteControl { |defaultChordType=\minor|
        MIDIdef.noteOn(\sunRootControl, { |vel, note, chan, src|
            if(vel > 0) {
                this.setChord(note, state[\chordType] ? defaultChordType);
            };
        });
        ("Root note control enabled. Default chord type: " ++ defaultChordType).postln;
    }

    setupChordDetection {
        MIDIdef.noteOn(\sunChordDetectOn, { |vel, note|
            if(vel > 0) {
                heldNotes.add(note);
                this.updateDetectedChord;
            };
        });

        MIDIdef.noteOff(\sunChordDetectOff, { |vel, note|
            heldNotes.remove(note);
        });

        "Chord detection enabled.".postln;
    }

    updateDetectedChord {
        var result;
        result = this.detectChordFromHeldNotes(heldNotes.asArray);

        if(result.notNil) {
            this.setChord(result[\rootMidi], result[\chordType]);
        };
    }

    detectChordFromHeldNotes { |notes|
        var pcs, defs, result;

        if(notes.size < 3) { ^nil };

        pcs = notes.collect { |n| n % 12 }.asSet.asArray.sort;
        defs = (
            major: [0, 4, 7],
            minor: [0, 3, 7],
            dim: [0, 3, 6],
            aug: [0, 4, 8],
            sus2: [0, 2, 7],
            sus4: [0, 5, 7],
            maj7: [0, 4, 7, 11],
            min7: [0, 3, 7, 10],
            dom7: [0, 4, 7, 10]
        );

        pcs.do { |candidateRootPc|
            var normalized;
            normalized = pcs.collect { |pc| (pc - candidateRootPc) % 12 }.sort;

            defs.keysValuesDo { |name, shape|
                if(normalized == shape) {
                    var lowestNote, rootMidi;
                    lowestNote = notes.minItem;
                    rootMidi = lowestNote + ((candidateRootPc - (lowestNote % 12)) % 12);

                    result = (
                        rootMidi: rootMidi,
                        chordType: name
                    );
                };
            };
        };

        ^result
    }

    setupMiniLab3DefaultMap {
        var lin;

        lin = { |value, min=0.0, max=1.0|
            value.linlin(0, 127, min, max);
        };

        MIDIdef.cc(\sunAmpCC, { |val| this.setAmp(lin.(val, 0.005, 0.18)); }, 21);
        MIDIdef.cc(\sunDensityCC, { |val| this.setDensity(lin.(val, 0.2, 6.0)); }, 22);
        MIDIdef.cc(\sunAttackCC, { |val| this.setAttack(lin.(val, 0.01, 2.5)); }, 23);
        MIDIdef.cc(\sunReleaseCC, { |val| this.setRelease(lin.(val, 0.2, 7.0)); }, 24);
        MIDIdef.cc(\sunReverbMixCC, { |val| this.setReverbMix(lin.(val, 0.0, 0.6)); }, 25);
        MIDIdef.cc(\sunRoomCC, { |val| this.setRoom(lin.(val, 0.2, 1.0)); }, 26);
        MIDIdef.cc(\sunDampCC, { |val| this.setDamp(lin.(val, 0.1, 0.9)); }, 27);

        MIDIdef.noteOn(\sunPadChordModes, { |vel, note|
            if(vel > 0) {
                case
                { note == 36 } { state[\chordType] = \minor; "Pad selected: minor".postln; }
                { note == 37 } { state[\chordType] = \major; "Pad selected: major".postln; }
                { note == 38 } { state[\chordType] = \maj7; "Pad selected: maj7".postln; }
                { note == 39 } { state[\chordType] = \min7; "Pad selected: min7".postln; }
                { note == 40 } { state[\chordType] = \add9; "Pad selected: add9".postln; }
                { note == 41 } { state[\chordType] = \min9; "Pad selected: min9".postln; }
                { note == 42 } { state[\chordType] = \maj9; "Pad selected: maj9".postln; }
                { note == 43 } { state[\chordType] = \dom13; "Pad selected: dom13".postln; };
            };
        });

        "Default MiniLab 3 mapping loaded.".postln;
    }
}