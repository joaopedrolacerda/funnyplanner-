//
//  FunnyPlannerTests.swift
//  FunnyPlannerTests
//
//  Testes das regras puras da sala (framework Testing). Não dependem do servidor
//  HTTP nem do FlyingFox — cobrem a lógica de negócio da v1.
//

import Testing
import Foundation
@testable import FunnyPlanner

struct PokerDeckTests {
    @Test func deckContainsFibonacciAndSpecials() {
        #expect(PokerDeck.cards == ["0", "1", "2", "3", "5", "8", "13", "21", "?", "☕"])
    }
}

struct AnonymousNameTests {
    @Test func namesAreSequentialAndOneBased() {
        #expect(RoomRules.anonymousName(for: 1) == "Usuário anônimo 1")
        #expect(RoomRules.anonymousName(for: 2) == "Usuário anônimo 2")
    }
}

struct ParticipantDTOTests {
    private func participant(_ name: String, vote: String?) -> Participant {
        Participant(id: UUID(), name: name, vote: vote)
    }

    @Test func votesAreHiddenWhileVoting() {
        let participants = [
            participant("Ana", vote: "5"),
            participant("Beto", vote: nil)
        ]
        let dtos = RoomRules.participantDTOs(from: participants, phase: .voting)

        #expect(dtos[0].hasVoted == true)
        #expect(dtos[0].vote == nil)   // oculto durante a votação
        #expect(dtos[1].hasVoted == false)
        #expect(dtos[1].vote == nil)
    }

    @Test func votesAreShownWhenRevealed() {
        let participants = [
            participant("Ana", vote: "5"),
            participant("Beto", vote: nil)
        ]
        let dtos = RoomRules.participantDTOs(from: participants, phase: .revealed)

        #expect(dtos[0].hasVoted == true)
        #expect(dtos[0].vote == "5")   // revelado
        #expect(dtos[1].hasVoted == false)
        #expect(dtos[1].vote == nil)
    }
}

struct LocalNetworkTests {
    @Test func ipv4AddressIsNilOrWellFormed() {
        // Não deve crashar; quando há Wi-Fi, retorna um IPv4 com 4 octetos.
        if let ip = LocalNetwork.ipv4Address() {
            let octets = ip.split(separator: ".")
            #expect(octets.count == 4)
        }
    }
}
