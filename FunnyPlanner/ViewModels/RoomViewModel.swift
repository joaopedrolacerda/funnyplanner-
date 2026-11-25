//
//  RoomViewModel.swift
//  FunnyPlanner
//
//  Orquestra o servidor e o hub de conexões para a UI do host. Mantém no `@MainActor`
//  um espelho do estado da sala (participantes e fase) atualizado via snapshots.
//

import Foundation
import Observation

@MainActor
@Observable
final class RoomViewModel {
    private(set) var isRunning = false
    private(set) var participants: [Participant] = []
    private(set) var phase: RoomPhase = .voting
    private(set) var joinURL: String?
    /// URL pública do túnel (ex.: Cloudflare) para acesso externo.
    var publicURL: String = ""
    /// Indica que o túnel está sendo criado (feedback na UI).
    private(set) var isStartingTunnel = false
    /// Indica que o `cloudflared` está sendo baixado (primeira execução).
    private(set) var isDownloadingTunnel = false
    var errorMessage: String?

    private let port: UInt16 = 8080
    private var hub: ConnectionHub?
    private var server: PlanningServer?
    private let tunnel = TunnelController()

    var votedCount: Int { participants.filter { $0.vote != nil }.count }

    /// Sobe o servidor, cria a sala e passa a aceitar participantes na rede local.
    func createRoom() async {
        let hub = ConnectionHub()
        await hub.setOnChange { [weak self] snapshot in
            Task { @MainActor in self?.apply(snapshot) }
        }
        let server = PlanningServer(port: port, hub: hub)
        do {
            try await server.start()
            self.hub = hub
            self.server = server
            isRunning = true
            joinURL = Self.makeURL(port: port)
            // Sobe o túnel público automaticamente, sem bloquear a abertura da sala.
            Task { await startTunnel() }
        } catch {
            errorMessage = "Não foi possível iniciar a sala: \(error.localizedDescription)"
        }
    }

    /// Cria o túnel público via cloudflared e preenche `publicURL` com a URL gerada.
    func startTunnel() async {
        guard isRunning, !isStartingTunnel else { return }
        isStartingTunnel = true
        errorMessage = nil
        defer {
            isStartingTunnel = false
            isDownloadingTunnel = false
        }
        do {
            let url = try await tunnel.start(port: port) { @MainActor [weak self] in
                self?.isDownloadingTunnel = true
            }
            isDownloadingTunnel = false
            // A sala pode ter sido encerrada enquanto o túnel subia.
            guard isRunning else {
                tunnel.stop()
                return
            }
            publicURL = url
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Encerra a sala: para o túnel, para o servidor e o link volta a ficar bloqueado.
    func endRoom() async {
        tunnel.stop()
        await server?.stop()
        server = nil
        hub = nil
        isRunning = false
        participants = []
        phase = .voting
        joinURL = nil
        publicURL = ""
    }

    func reveal() async { await hub?.reveal() }
    func newRound() async { await hub?.newRound() }

    private func apply(_ snapshot: RoomSnapshot) {
        participants = snapshot.participants
        phase = snapshot.phase
    }

    private static func makeURL(port: UInt16) -> String {
        if let ip = LocalNetwork.ipv4Address() {
            return "http://\(ip):\(port)/"
        }
        return "http://localhost:\(port)/"
    }
}
