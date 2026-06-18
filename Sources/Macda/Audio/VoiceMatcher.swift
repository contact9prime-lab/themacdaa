import Foundation

/// One transcribed chunk plus its voiceprint, collected during a session.
struct VoiceSegment {
    let embedding: [Float]
    let text: String
    let audioPath: String
}

/// Groups session segments into speakers: matches each to a known person's
/// enrolled voiceprint when similar enough, otherwise clusters the unknowns so
/// each distinct new voice can be surfaced for tagging (and enrollment).
struct VoiceMatcher {
    let threshold: Float

    private final class Cluster {
        var person: Person?
        var embeddings: [[Float]] = []
        var quotes: [String] = []
        var centroid: [Float] = []
        var bestAudioPath = ""        // clip with the most speech, for playback
        private var bestLen = -1
        func add(_ seg: VoiceSegment) {
            embeddings.append(seg.embedding)
            if quotes.count < 3, !seg.text.isEmpty { quotes.append(seg.text) }
            if seg.text.count > bestLen, !seg.audioPath.isEmpty {
                bestLen = seg.text.count
                bestAudioPath = seg.audioPath
            }
            centroid = VoiceEmbedder.centroid(embeddings)
        }
    }

    func assign(segments: [VoiceSegment], people: [Person]) -> [DetectedSpeaker] {
        let enrolled = people.filter { !$0.voicePrint.isEmpty }
        var clusters: [Cluster] = []

        for seg in segments where !seg.embedding.isEmpty {
            if let person = bestPerson(seg.embedding, enrolled) {
                let c = clusters.first { $0.person?.id == person.id } ?? {
                    let nc = Cluster(); nc.person = person; clusters.append(nc); return nc
                }()
                c.add(seg)
            } else if let c = bestUnknownCluster(seg.embedding, clusters) {
                c.add(seg)
            } else {
                let nc = Cluster(); nc.add(seg); clusters.append(nc)
            }
        }

        var speakers: [DetectedSpeaker] = []
        var unknownIndex = 1
        for c in clusters {
            let label: String
            if let p = c.person { label = p.name } else { label = "Speaker \(unknownIndex)"; unknownIndex += 1 }
            speakers.append(DetectedSpeaker(label: label,
                                            sampleQuote: c.quotes.first ?? "",
                                            personID: c.person?.id,
                                            embedding: c.centroid,
                                            sampleAudioPath: c.bestAudioPath))
        }
        return speakers
    }

    private func bestPerson(_ emb: [Float], _ people: [Person]) -> Person? {
        var best: (Person, Float)?
        for p in people {
            let sim = VoiceEmbedder.cosine(emb, p.voicePrint)
            if sim >= threshold, sim > (best?.1 ?? -1) { best = (p, sim) }
        }
        return best?.0
    }

    private func bestUnknownCluster(_ emb: [Float], _ clusters: [Cluster]) -> Cluster? {
        var best: (Cluster, Float)?
        for c in clusters where c.person == nil {
            let sim = VoiceEmbedder.cosine(emb, c.centroid)
            if sim >= threshold, sim > (best?.1 ?? -1) { best = (c, sim) }
        }
        return best?.0
    }
}
