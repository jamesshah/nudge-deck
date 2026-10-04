import Foundation

// Convex `v.number()` values arrive as JSON floats, so every number here is a Double.

enum CardKind: String, Decodable {
    case action
    case counter
}

enum PlayState: String, Decodable {
    case pending
    case proofSubmitted
    case completed
    case refused
    case countered
}

enum ProofType: String, Decodable, CaseIterable, Identifiable {
    case text
    case photo
    case audio

    var id: String { rawValue }
}

enum CoupleStatus: String, Decodable {
    case waiting
    case active
    case ended
}

struct Me: Decodable, Equatable {
    let id: String
    let name: String
    let timeZone: String
    let utcOffsetMinutes: Double
    let quietStartMinutes: Double?
    let quietEndMinutes: Double?
    let coupleId: String?
    let isDevAccount: Bool

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, timeZone, utcOffsetMinutes, quietStartMinutes, quietEndMinutes, coupleId, isDevAccount
    }
}

struct Player: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let timeZone: String
    let utcOffsetMinutes: Double
    let quietStartMinutes: Double?
    let quietEndMinutes: Double?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, timeZone, utcOffsetMinutes, quietStartMinutes, quietEndMinutes
    }

    var quietHours: QuietHours? {
        guard let start = quietStartMinutes, let end = quietEndMinutes else { return nil }
        return QuietHours(startMinutes: Int(start), endMinutes: Int(end))
    }
}

struct Couple: Decodable, Equatable {
    let id: String
    let status: CoupleStatus
    let inviteCode: String
    let timeframeDays: Double
    let startedAt: Double?
    let endsAt: Double?
    let me: Player
    let partner: Player?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case status, inviteCode, timeframeDays, startedAt, endsAt, me, partner
    }
}

struct HandCard: Decodable, Equatable, Identifiable {
    let handId: String
    let cardId: String
    let title: String
    let body: String
    let category: String
    let kind: CardKind
    let isCustom: Bool
    let stolenFromName: String?

    var id: String { handId }
}

struct Hand: Decodable, Equatable {
    let cards: [HandCard]
    let usedCount: Double
    let partnerCardsLeft: Double
    let customCardsLeftToWrite: Double

    static let empty = Hand(cards: [], usedCount: 0, partnerCardsLeft: 0, customCardsLeftToWrite: 0)

    var actionCards: [HandCard] { cards.filter { $0.kind == .action } }
    var counterCards: [HandCard] { cards.filter { $0.kind == .counter } }
}

struct Play: Decodable, Equatable, Identifiable {
    let id: String
    let cardId: String
    let title: String
    let body: String
    let category: String
    let kind: CardKind
    let fromId: String
    let toId: String
    let fromName: String
    let toName: String
    let state: PlayState
    let stackedOnPlayId: String?
    let stackedOnTitle: String?
    let counteredPlayId: String?
    let counteredTitle: String?
    let delivered: Bool
    let deliverAt: Double
    let playedAt: Double
    let respondedAt: Double?
    let proofType: ProofType?
    let proofText: String?
    let proofUrl: String?
    let proofRejectedNote: String?
    let stolenCardTitle: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case cardId, title, body, category, kind, fromId, toId, fromName, toName, state
        case stackedOnPlayId, stackedOnTitle, counteredPlayId, counteredTitle
        case delivered, deliverAt, playedAt, respondedAt
        case proofType, proofText, proofUrl, proofRejectedNote, stolenCardTitle
    }

    var playedDate: Date { Date(timeIntervalSince1970: playedAt / 1000) }
    var deliverDate: Date { Date(timeIntervalSince1970: deliverAt / 1000) }

    /// Storage URLs from a local backend use loopback; align to the app's Convex host.
    var reachableProofURL: URL? {
        guard let proofUrl else { return nil }
        return URL(string: AppConfig.alignStorageURL(proofUrl))
    }
}

struct Inbox: Decodable, Equatable {
    let incoming: [Play]
    let toReview: [Play]
    let waitingOnPartner: [Play]

    static let empty = Inbox(incoming: [], toReview: [], waitingOnPartner: [])

    var needsAttentionCount: Int {
        incoming.filter { $0.state == .pending }.count + toReview.count
    }
}

struct RecapPlayer: Decodable, Equatable, Identifiable {
    let userId: String
    let name: String
    let played: Double
    let completedByPartner: Double
    let refusedByPartner: Double
    let refused: Double
    let countersUsed: Double
    let cardsStolen: Double
    let cardsLeft: Double

    var id: String { userId }
}

struct Recap: Decodable, Equatable {
    let status: CoupleStatus
    let startedAt: Double?
    let endsAt: Double?
    let players: [RecapPlayer]
}

struct UploadResponse: Decodable {
    let storageId: String
}
