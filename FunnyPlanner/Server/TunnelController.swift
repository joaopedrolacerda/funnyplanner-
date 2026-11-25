//
//  TunnelController.swift
//  FunnyPlanner
//
//  Sobe um "quick tunnel" do Cloudflare (`cloudflared`) apontando para a porta local
//  e captura a URL pública gerada; encerra o processo ao finalizar a sala.
//
//  IMPORTANTE: requer o App Sandbox DESLIGADO — sob sandbox o macOS impede lançar
//  executáveis externos. Sem sandbox, o servidor local segue aceitando conexões
//  normalmente (o entitlement network.server só é exigido quando sandboxed).
//

import Foundation

nonisolated final class TunnelController {

    enum TunnelError: LocalizedError {
        case downloadFailed(String)
        case urlNotDetected
        case launchFailed(String)

        var errorDescription: String? {
            switch self {
            case let .downloadFailed(reason):
                return "Não consegui baixar o cloudflared: \(reason). Verifique a internet ou instale com: brew install cloudflared"
            case .urlNotDetected:
                return "Não consegui obter a URL pública do túnel (tempo esgotado)."
            case let .launchFailed(reason):
                return "Falha ao iniciar o túnel: \(reason). O App Sandbox precisa estar desligado."
            }
        }
    }

    private let lock = NSLock()
    private var process: Process?

    /// Caminhos comuns do binário instalado via Homebrew (Apple Silicon / Intel) ou manual,
    /// usados como fallback caso a cópia embutida no app não esteja disponível.
    private static let candidatePaths = [
        "/opt/homebrew/bin/cloudflared",
        "/usr/local/bin/cloudflared",
        "/usr/bin/cloudflared"
    ]

    /// Local onde o app guarda o `cloudflared` baixado automaticamente:
    /// `~/Library/Application Support/FunnyPlanner/cloudflared`.
    private static var downloadedBinaryURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "FunnyPlanner", directoryHint: .isDirectory)
            .appending(path: "cloudflared")
    }

    /// Release oficial do cloudflared para macOS na arquitetura atual.
    private static var downloadURL: URL? {
        #if arch(arm64)
        let asset = "cloudflared-darwin-arm64.tgz"
        #else
        let asset = "cloudflared-darwin-amd64.tgz"
        #endif
        return URL(string: "https://github.com/cloudflare/cloudflared/releases/latest/download/\(asset)")
    }

    /// Prefere o `cloudflared` embutido no bundle (Contents/Resources); depois o já baixado
    /// pelo app; por fim, uma instalação no sistema.
    private static func resolveBinary() -> String? {
        let bundled = Bundle.main.path(forResource: "cloudflared", ofType: nil)
        return ([bundled, downloadedBinaryURL.path].compactMap { $0 } + candidatePaths)
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Baixa o `.tgz` do GitHub, extrai o binário para Application Support e o torna executável.
    private static func downloadBinary() async throws -> String {
        let destination = downloadedBinaryURL
        let directory = destination.deletingLastPathComponent()
        let fileManager = FileManager.default
        guard let downloadURL else { throw TunnelError.downloadFailed("URL inválida") }

        do {
            let (archive, response) = try await URLSession.shared.download(from: downloadURL)
            defer { try? fileManager.removeItem(at: archive) }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw TunnelError.downloadFailed("HTTP \(http.statusCode)")
            }

            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try? fileManager.removeItem(at: destination)

            // O pacote contém um único arquivo `cloudflared`; extrai direto no diretório final.
            let tar = Process()
            tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            tar.arguments = ["-xzf", archive.path, "-C", directory.path]
            try tar.run()
            tar.waitUntilExit()
            guard tar.terminationStatus == 0 else {
                throw TunnelError.downloadFailed("falha ao extrair o arquivo")
            }

            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        } catch let error as TunnelError {
            throw error
        } catch {
            throw TunnelError.downloadFailed(error.localizedDescription)
        }

        guard fileManager.isExecutableFile(atPath: destination.path) else {
            throw TunnelError.downloadFailed("binário não encontrado após extração")
        }
        return destination.path
    }

    /// Inicia o túnel para `http://localhost:<port>` e devolve a URL pública
    /// (`https://…trycloudflare.com`). Se o `cloudflared` não estiver disponível,
    /// baixa-o automaticamente antes (avisando via `onDownloadStart`).
    func start(port: UInt16, onDownloadStart: @Sendable () async -> Void = {}) async throws -> String {
        let binary: String
        if let existing = Self.resolveBinary() {
            binary = existing
        } else {
            await onDownloadStart()
            binary = try await Self.downloadBinary()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["tunnel", "--no-autoupdate", "--url", "http://localhost:\(port)"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw TunnelError.launchFailed(error.localizedDescription)
        }

        lock.lock(); self.process = process; lock.unlock()

        let handle = pipe.fileHandleForReading
        let resumer = ResumeOnce<String>()
        let buffer = DataBox()

        handle.readabilityHandler = { fileHandle in
            let chunk = fileHandle.availableData
            guard !chunk.isEmpty else { return }   // EOF
            buffer.append(chunk)
            if let text = buffer.string, let url = Self.extractURL(from: text) {
                resumer.fulfill(url)
                buffer.reset()
                // Segue drenando o pipe (descartando) para o cloudflared não travar
                // ao encher o buffer de saída numa sessão longa.
                fileHandle.readabilityHandler = { _ = $0.availableData }
            }
        }

        let timeout = Task {
            try? await Task.sleep(for: .seconds(25))
            resumer.fail(TunnelError.urlNotDetected)
        }

        defer { timeout.cancel() }
        do {
            return try await resumer.value()
        } catch {
            stop()
            throw error
        }
    }

    /// Encerra o túnel.
    func stop() {
        lock.lock(); let running = process; process = nil; lock.unlock()
        running?.terminate()
    }

    /// Extrai a URL do quick tunnel (`https://<algo>.trycloudflare.com`) de um texto.
    static func extractURL(from text: String) -> String? {
        guard let range = text.range(
            of: #"https://[a-zA-Z0-9.-]+\.trycloudflare\.com"#,
            options: .regularExpression
        ) else { return nil }
        return String(text[range])
    }
}

// MARK: - Auxiliares thread-safe

/// Entrega um valor assíncrono exatamente uma vez, vindo de callbacks em outra thread.
private final class ResumeOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var pending: Result<T, Error>?

    func value() async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            lock.lock()
            if let pending {
                lock.unlock()
                cont.resume(with: pending)
            } else {
                continuation = cont
                lock.unlock()
            }
        }
    }

    func fulfill(_ value: T) { complete(.success(value)) }
    func fail(_ error: Error) { complete(.failure(error)) }

    private func complete(_ result: Result<T, Error>) {
        lock.lock()
        if let cont = continuation {
            continuation = nil
            lock.unlock()
            cont.resume(with: result)
        } else {
            if pending == nil { pending = result }
            lock.unlock()
        }
    }
}

/// Buffer de bytes acumulados do pipe, acessível com segurança entre threads.
private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) { lock.lock(); data.append(chunk); lock.unlock() }
    func reset() { lock.lock(); data.removeAll(keepingCapacity: false); lock.unlock() }
    var string: String? {
        lock.lock(); defer { lock.unlock() }
        return String(data: data, encoding: .utf8)
    }
}
