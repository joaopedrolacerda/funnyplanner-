//
//  PlanningServer.swift
//  FunnyPlanner
//
//  Servidor HTTP embarcado (FlyingFox) da sala. Serve a página do participante em
//  `GET /` e o WebSocket em `GET /ws`. Enquanto o servidor está rodando a sala está
//  aberta; ao parar, as rotas deixam de responder e a sala fica "bloqueada".
//

import Foundation
import FlyingFox
import FlyingSocks

nonisolated final class PlanningServer {
    let port: UInt16
    private let hub: ConnectionHub
    private var server: HTTPServer?
    private var runTask: Task<Void, Error>?

    init(port: UInt16 = 8080, hub: ConnectionHub) {
        self.port = port
        self.hub = hub
    }

    /// Sobe o servidor e começa a aceitar conexões na rede local.
    func start() async throws {
        // Bind explícito em IPv4 0.0.0.0: o padrão `HTTPServer(port:)` escuta só em
        // IPv6 (`::`), o que faz o navegador (que acessa pelo IP IPv4 da LAN) dar timeout.
        let server = HTTPServer(address: .inet(port: port))

        await server.appendRoute("GET /") { _ in
            HTTPResponse(
                statusCode: .ok,
                headers: [.contentType: "text/html; charset=utf-8"],
                body: Data(WebClientPage.html.utf8)
            )
        }

        await server.appendRoute("GET /ws", to: .webSocket(RoomWSHandler(hub: hub)))

        self.server = server
        runTask = Task { try await server.run() }
        try await server.waitUntilListening()
    }

    /// Para o servidor: as rotas deixam de responder e a sala fica bloqueada.
    func stop() async {
        await server?.stop(timeout: 1)
        runTask?.cancel()
        server = nil
        runTask = nil
    }
}

/// Faz a ponte entre o WebSocket de um navegador e o `ConnectionHub`: registra a
/// conexão, repassa os votos recebidos e entrega o stream de saída (estado da sala).
nonisolated struct RoomWSHandler: WSMessageHandler {
    let hub: ConnectionHub

    func makeMessages(for client: AsyncStream<WSMessage>) async throws -> AsyncStream<WSMessage> {
        let (id, outbound) = await hub.connect()

        Task {
            for await message in client {
                if case let .text(text) = message {
                    await hub.handleClientText(text, from: id)
                }
            }
            await hub.disconnect(id)
        }

        return outbound
    }
}
