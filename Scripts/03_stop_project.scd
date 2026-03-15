(
if(~sun.notNil) {
    ~sun.clearMidiDefs;
    ~sun.cleanup;
    ~sun = nil;
    "Project stopped and cleaned.".postln;
} {
    "No active SunArpeggios instance found.".postln;
};
)