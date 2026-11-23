//
//  KETranscriptShim.swift
//  Kiln's engine
//
//  The two calls KETranscript.swift makes that differ between engines. The
//  engine before §1.3 gets its own copy (Tools/KilnDiff/BaselineShim.swift).
//

extension KInterpreter {
    /// An action, as the probe fires it; transcripts run headless.
    func _transcriptFire(_ f: KFunction, _ args: [KV], canWait: Bool) {
        headless = true
        runAction(f, args, canWait: canWait)
    }

    /// Runs the tasks the action started, to their end or their next real wait.
    func _transcriptDrain() {
        headless = true
        drain()
    }
}
