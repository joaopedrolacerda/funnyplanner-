//
//  Room.swift
//  FunnyPlanner
//
//  Modelos da sala de planning poker e DTOs do protocolo WebSocket.
//  Tudo vive em memória — nada é persistido (sessão da sala).
//

import Foundation

/// Um participante conectado à sala. A identidade só existe enquanto a conexão vive.
nonisolated struct Participant: Identifiable, Sendable, Equatable {
    let id: UUID
    var name: String
    var vote: String?
}

/// Fase atual da rodada de votação.
nonisolated enum RoomPhase: String, Sendable, Codable {
    /// Participantes estão votando; os votos ficam ocultos.
    case voting
    /// Votos revelados para todos.
    case revealed
}

/// Baralho usado na votação: sequência de Fibonacci + cartas especiais.
nonisolated enum PokerDeck {
    static let cards: [String] = ["0", "1", "2", "3", "5", "8", "13", "21", "?", "☕"]
}

/// Snapshot imutável do estado da sala, entregue à UI do host.
nonisolated struct RoomSnapshot: Sendable, Equatable {
    var phase: RoomPhase
    var participants: [Participant]
}

// MARK: - Protocolo WebSocket (servidor <-> navegador)

/// Mensagem recebida do navegador do participante. Ex.: `{"type":"vote","value":"5"}`.
nonisolated struct ClientMessage: Codable, Sendable {
    let type: String
    let value: String?
}

/// Enviada uma vez, logo após o participante conectar, com sua identidade de sessão.
nonisolated struct WelcomeMessage: Codable, Sendable {
    var type = "welcome"
    let id: String
    let name: String
}

/// Representação de um participante enviada ao navegador. O `vote` só vem preenchido
/// quando a fase é `.revealed`.
nonisolated struct ParticipantDTO: Codable, Sendable {
    let id: String
    let name: String
    let hasVoted: Bool
    let vote: String?
}

/// Estado completo da sala, transmitido (broadcast) a todos os navegadores a cada mudança.
nonisolated struct RoomStateMessage: Codable, Sendable {
    var type = "state"
    let phase: RoomPhase
    let cards: [String]
    let participants: [ParticipantDTO]
}

// MARK: - Regras puras da sala (testáveis, sem dependências de rede)

enum RoomRules {
    /// Nome de sessão de um participante anônimo, a partir de um contador 1-based.
    static func anonymousName(for counter: Int) -> String {
        "Usuário anônimo \(counter)"
    }

    /// Converte participantes em DTOs para o navegador, ocultando os votos enquanto
    /// a fase for `.voting` e revelando-os em `.revealed`.
    static func participantDTOs(from participants: [Participant], phase: RoomPhase) -> [ParticipantDTO] {
        participants.map { participant in
            ParticipantDTO(
                id: participant.id.uuidString,
                name: participant.name,
                hasVoted: participant.vote != nil,
                vote: phase == .revealed ? participant.vote : nil
            )
        }
    }
}
