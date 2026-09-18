import Foundation

struct TalixProject: Codable, Identifiable, Sendable, Equatable {
    struct Client: Codable, Sendable, Equatable {
        let id: String
        let name: String
    }

    let id: String
    let name: String
    var status: String?
    var client: Client?
    var rate: Double?

    init(id: String, name: String, status: String? = nil, client: Client? = nil, rate: Double? = nil) {
        self.id = id
        self.name = name
        self.status = status
        self.client = client
        self.rate = rate
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        status = try values.decodeIfPresent(String.self, forKey: .status)
        client = try values.decodeIfPresent(Client.self, forKey: .client)
        if let number = try? values.decode(Double.self, forKey: .rate) {
            guard number.isFinite, number >= 0 else { throw TalixEntryDraft.DraftError.invalidRate }
            rate = number
        } else if let string = try values.decodeIfPresent(String.self, forKey: .rate) {
            guard let number = Double(string), number.isFinite, number >= 0 else {
                throw TalixEntryDraft.DraftError.invalidRate
            }
            rate = number
        }
    }
}
