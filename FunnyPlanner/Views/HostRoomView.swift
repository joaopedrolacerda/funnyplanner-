//
//  HostRoomView.swift
//  FunnyPlanner
//
//  Tela do host com a sala aberta: link + QR para entrar, lista de participantes
//  e controles da rodada (revelar, nova rodada, encerrar).
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct HostRoomView: View {
    @Bindable var viewModel: RoomViewModel

    private var trimmedPublicURL: String {
        viewModel.publicURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            Divider()
            externalAccessSection
            Divider()
            participantsSection
            Spacer(minLength: 0)
            controls
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 600)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sala aberta 🟢")
                    .font(.title2.bold())
                Text("Compartilhe o link com o time (mesma rede Wi-Fi):")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                if let url = viewModel.joinURL {
                    HStack(spacing: 8) {
                        Text(url)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Button {
                            copyToClipboard(url)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Copiar link")
                    }
                }
            }
            Spacer()
            if let url = viewModel.joinURL, let qr = QRCode.cgImage(from: url) {
                Image(qr, scale: 1, label: Text("QR code da sala"))
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 110, height: 110)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var externalAccessSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Acesso externo (internet)")
                .font(.headline)

            if trimmedPublicURL.isEmpty {
                Text("Gere um link público (Cloudflare) para quem está fora da sua rede.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await viewModel.startTunnel() }
                } label: {
                    if viewModel.isStartingTunnel {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(viewModel.isDownloadingTunnel ? "Baixando cloudflared…" : "Criando link público…")
                        }
                    } else {
                        Label("Gerar link público", systemImage: "globe")
                    }
                }
                .disabled(viewModel.isStartingTunnel)
                if let error = viewModel.errorMessage, !viewModel.isStartingTunnel {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } else {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Link público ativo 🌐").font(.subheadline.bold())
                        HStack(spacing: 8) {
                            Text(trimmedPublicURL)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button {
                                copyToClipboard(trimmedPublicURL)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .help("Copiar link público")
                        }
                    }
                    Spacer()
                    if let qr = QRCode.cgImage(from: trimmedPublicURL) {
                        Image(qr, scale: 1, label: Text("QR code do link público"))
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 100, height: 100)
                            .background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private var participantsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Participantes (\(viewModel.participants.count))")
                .font(.headline)
            if viewModel.participants.isEmpty {
                Text("Aguardando participantes entrarem…")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.participants) { participant in
                    HStack {
                        Text(participant.name)
                        Spacer()
                        statusBadge(for: participant)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    @ViewBuilder
    private func statusBadge(for participant: Participant) -> some View {
        if viewModel.phase == .revealed {
            Text(participant.vote ?? "—")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.blue)
        } else if participant.vote != nil {
            Label("votou", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)
        } else {
            Text("aguardando")
                .foregroundStyle(.orange)
        }
    }

    private var controls: some View {
        HStack {
            if viewModel.phase == .voting {
                Button("Revelar votos") {
                    Task { await viewModel.reveal() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.votedCount == 0)
            } else {
                Button("Nova rodada") {
                    Task { await viewModel.newRound() }
                }
                .buttonStyle(.borderedProminent)
            }
            Spacer()
            Button("Encerrar sala", role: .destructive) {
                Task { await viewModel.endRoom() }
            }
        }
    }

    private func copyToClipboard(_ value: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
    }
}
