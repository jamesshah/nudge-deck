import Combine
import ConvexMobile
import Foundation

/// Live game state for the signed-in player, backed by Convex subscriptions.
@MainActor
final class GameStore: ObservableObject {
    @Published private(set) var couple: Couple?
    @Published private(set) var coupleLoaded = false
    @Published private(set) var hand: Hand = .empty
    @Published private(set) var inbox: Inbox = .empty
    @Published private(set) var timeline: [Play] = []
    @Published private(set) var recap: Recap?
    @Published var errorMessage: String?
    @Published private(set) var isWorking = false

    let token: String
    /// Nil only for previews, which must never open a connection.
    private let client: ConvexClient?
    private var subscriptions = Set<AnyCancellable>()

    init(token: String, client: ConvexClient = Backend.client) {
        self.token = token
        self.client = client
        subscribeAll()
    }

    #if DEBUG
    /// Offline store for SwiftUI previews: fixed state, no subscriptions, and mutations are no-ops.
    init(
        previewCouple couple: Couple?,
        hand: Hand = .empty,
        inbox: Inbox = .empty,
        timeline: [Play] = [],
        recap: Recap? = nil,
        isWorking: Bool = false
    ) {
        token = "preview"
        client = nil
        self.couple = couple
        coupleLoaded = true
        self.hand = hand
        self.inbox = inbox
        self.timeline = timeline
        self.recap = recap
        self.isWorking = isWorking
    }
    #endif

    var partner: Player? { couple?.partner }
    var partnerName: String { couple?.partner?.name ?? "your partner" }

    // MARK: Subscriptions

    private func subscribeAll() {
        watch("couples:current", as: Couple?.self) { [weak self] value in
            self?.couple = value
            self?.coupleLoaded = true
            NotificationService.shared.coupleDidUpdate(value)
        }
        watch("cards:myHand", as: Hand.self) { [weak self] in self?.hand = $0 }
        watch("plays:inbox", as: Inbox.self) { [weak self] value in
            self?.inbox = value
            NotificationService.shared.inboxDidUpdate(value)
        }
        watch("plays:timeline", as: [Play].self) { [weak self] in self?.timeline = $0 }
        watch("couples:recap", as: Recap?.self) { [weak self] in self?.recap = $0 }
    }

    private func watch<T: Decodable>(_ name: String, as type: T.Type, onValue: @escaping (T) -> Void) {
        client?
            .subscribe(to: name, with: ["sessionToken": token], yielding: type)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.errorMessage = Backend.message(for: error)
                    }
                },
                receiveValue: onValue
            )
            .store(in: &subscriptions)
    }

    // MARK: Calls

    /// Runs a mutation that returns null, surfacing rule errors to the UI. Returns true on success.
    @discardableResult
    func run(_ name: String, _ args: [String: ConvexEncodable?] = [:]) async -> Bool {
        guard let client else { return false }
        var fullArgs = args
        fullArgs["sessionToken"] = token
        isWorking = true
        defer { isWorking = false }
        do {
            try await client.mutation(name, with: fullArgs)
            return true
        } catch {
            errorMessage = Backend.message(for: error)
            return false
        }
    }

    func syncDeviceTime() async {
        guard let client else { return }
        var args = Backend.deviceTimeArgs
        args["sessionToken"] = token
        try? await client.mutation("users:updateProfile", with: args)
    }

    // MARK: Pairing

    func createCouple(timeframeDays: Int) async {
        await run("couples:create", ["timeframeDays": Double(timeframeDays)])
    }

    @discardableResult
    func joinCouple(code: String) async -> Bool {
        await run("couples:join", ["inviteCode": GameFormatting.normalizedInviteCode(code)])
    }

    func cancelInvite() async {
        await run("couples:cancelInvite")
    }

    @discardableResult
    func unpair() async -> Bool {
        await run("couples:unpair")
    }

    @discardableResult
    func startNewSeason(timeframeDays: Int) async -> Bool {
        await run("couples:startNewSeason", ["timeframeDays": Double(timeframeDays)])
    }

    // MARK: Cards

    @discardableResult
    func play(_ card: HandCard, stackedOn play: Play?) async -> Bool {
        var args: [String: ConvexEncodable?] = ["handId": card.handId]
        if let play { args["stackedOnPlayId"] = play.id }
        return await run("plays:playCard", args)
    }

    @discardableResult
    func counter(_ play: Play, with card: HandCard) async -> Bool {
        await run("plays:counter", ["handId": card.handId, "targetPlayId": play.id])
    }

    @discardableResult
    func refuse(_ play: Play) async -> Bool {
        await run("plays:refuse", ["playId": play.id])
    }

    @discardableResult
    func completeWithText(_ play: Play, text: String) async -> Bool {
        await run("plays:completeWithProof", ["playId": play.id, "proofType": "text", "proofText": text])
    }

    @discardableResult
    func completeWithFile(_ play: Play, type: ProofType, data: Data, contentType: String, caption: String?) async -> Bool {
        guard GameFormatting.isProofFileWithinLimit(data) else {
            errorMessage = GameFormatting.proofFileTooLargeMessage(for: type)
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let storageId = try await uploadFile(data: data, contentType: contentType)
            var args: [String: ConvexEncodable?] = [
                "playId": play.id,
                "proofType": type.rawValue,
                "proofStorageId": storageId,
            ]
            if let caption, !caption.isEmpty { args["proofText"] = caption }
            return await run("plays:completeWithProof", args)
        } catch {
            errorMessage = Backend.message(for: error)
            return false
        }
    }

    func acceptProof(_ play: Play) async {
        await run("plays:acceptProof", ["playId": play.id])
    }

    func rejectProof(_ play: Play, note: String) async {
        await run("plays:rejectProof", ["playId": play.id, "note": note])
    }

    @discardableResult
    func createCustomCard(title: String, body: String) async -> Bool {
        await run("cards:createCustom", ["title": title, "body": body])
    }

    // MARK: Settings

    @discardableResult
    func setQuietHours(startMinutes: Int?, endMinutes: Int?) async -> Bool {
        var args: [String: ConvexEncodable?] = ["startMinutes": nil, "endMinutes": nil]
        if let startMinutes, let endMinutes {
            args["startMinutes"] = Double(startMinutes)
            args["endMinutes"] = Double(endMinutes)
        }
        return await run("users:setQuietHours", args)
    }

    func rename(to name: String) async {
        var args = Backend.deviceTimeArgs
        args["name"] = name
        await run("users:updateProfile", args)
    }

    // MARK: Uploads

    private func uploadFile(data: Data, contentType: String) async throws -> String {
        guard let client else { throw UploadError.failed }
        let uploadURLString: String = try await client.mutation(
            "plays:generateUploadUrl", with: ["sessionToken": token])
        // Local Convex returns 127.0.0.1; rewrite to the host the app actually uses.
        guard let url = URL(string: AppConfig.alignStorageURL(uploadURLString)) else {
            throw UploadError.badURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (responseData, response) = try await URLSession.shared.upload(for: request, from: data)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UploadError.failed
        }
        return try JSONDecoder().decode(UploadResponse.self, from: responseData).storageId
    }

    enum UploadError: LocalizedError {
        case badURL
        case failed

        var errorDescription: String? {
            switch self {
            case .badURL: return "The upload link was invalid. Please try again."
            case .failed: return "Your proof couldn't be uploaded. Please try again."
            }
        }
    }
}
