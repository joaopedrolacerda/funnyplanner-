//
//  ConnectionHub.swift
//  FunnyPlanner
//
//  Fonte única de verdade do estado da sala. Guarda os participantes conectados,
//  o canal de saída (WebSocket) de cada um e faz o broadcast do estado. Como é um
//  `actor`, o acesso ao estado é serializado e seguro entre conexões concorrentes.
//

import Foundation
import FlyingFox

actor ConnectionHub {
    private var participants: [Participant] = []
    private var continuations: [UUID: AsyncStream<WSMessage>.Continuation] = [:]
    private var phase: RoomPhase = .voting
    private var anonymousCounter = 0

    /// Notifica a UI do host a cada mudança de estado. Definido pelo `RoomViewModel`.
    var onChange: (@Sendable (RoomSnapshot) -> Void)?

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func setOnChange(_ handler: @escaping @Sendable (RoomSnapshot) -> Void) {
        onChange = handler
        handler(snapshot())
    }

    // MARK: - Ciclo de vida das conexões

    /// Registra uma nova conexão, cria um participante anônimo e devolve o `id` da
    /// sessão junto com o stream de mensagens que o servidor envia a esse navegador.
    func connect() -> (id: UUID, outbound: AsyncStream<WSMessage>) {
        anonymousCounter += 1
        let participant = Participant(
            id: UUID(),
            name: RoomRules.anonymousName(for: anonymousCounter),
            vote: nil
        )
        participants.append(participant)

        let (stream, continuation) = AsyncStream<WSMessage>.makeStream(
            bufferingPolicy: .unbounded
        )
        continuations[participant.id] = continuation

        if let welcome = encode(WelcomeMessage(id: participant.id.uuidString, name: participant.name)) {
            continuation.yield(.text(welcome))
        }

        broadcastState()
        notifyUI()
        return (participant.id, stream)
    }

    func disconnect(_ id: UUID) {
        continuations[id]?.finish()
        continuations[id] = nil
        participants.removeAll { $0.id == id }
        broadcastState()
        notifyUI()
    }

    // MARK: - Mensagens recebidas do navegador

    func handleClientText(_ text: String, from id: UUID) {
        guard let data = text.data(using: .utf8),
              let message = try? decoder.decode(ClientMessage.self, from: data)
        else { return }

        switch message.type {
        case "vote":
            if let value = message.value { applyVote(value, from: id) }
        default:
            break
        }
    }

    // MARK: - Ações da sala

    func applyVote(_ value: String, from id: UUID) {
        guard phase == .voting,
              PokerDeck.cards.contains(value),
              let index = participants.firstIndex(where: { $0.id == id })
        else { return }
        // Votar na mesma carta de novo cancela o voto (toggle).
        participants[index].vote = participants[index].vote == value ? nil : value
        broadcastState()
        notifyUI()
    }

    func reveal() {
        phase = .revealed
        broadcastState()
        notifyUI()
    }

    func newRound() {
        phase = .voting
        for index in participants.indices { participants[index].vote = nil }
        broadcastState()
        notifyUI()
    }

    // MARK: - Broadcast / snapshot

    private func broadcastState() {
        let dtos = RoomRules.participantDTOs(from: participants, phase: phase)
        let message = RoomStateMessage(phase: phase, cards: PokerDeck.cards, participants: dtos)
        guard let json = encode(message) else { return }
        for continuation in continuations.values {
            continuation.yield(.text(json))
        }
    }

    private func notifyUI() {
        onChange?(snapshot())
    }

    private func snapshot() -> RoomSnapshot {
        RoomSnapshot(phase: phase, participants: participants)
    }

    private func encode<T: Encodable>(_ value: T) -> String? {
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
