//
//  ContentView.swift
//  FunnyPlanner
//
//  Ponto de entrada da UI: tela inicial para criar a sala ou, quando ativa, a
//  tela do host (`HostRoomView`).
//

import SwiftUI

struct ContentView: View {
    @State private var viewModel = RoomViewModel()

    var body: some View {
        if viewModel.isRunning {
            HostRoomView(viewModel: viewModel)
        } else {
            StartView(viewModel: viewModel)
        }
    }
}

/// Tela inicial: um único botão para abrir a sala de planning.
struct StartView: View {
    let viewModel: RoomViewModel
    @State private var isCreating = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "suit.club.fill")
                .font(.system(size: 56))
                .foregroundStyle(.blue)
            Text("FunnyPlanner")
                .font(.largeTitle.bold())
            Text("Crie uma sala de planning poker e convide o time pelo navegador.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)

            Button {
                isCreating = true
                Task {
                    await viewModel.createRoom()
                    isCreating = false
                }
            } label: {
                Text("Criar sala")
                    .frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isCreating)

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .frame(minWidth: 420, minHeight: 420)
    }
}

#Preview {
    ContentView()
}
