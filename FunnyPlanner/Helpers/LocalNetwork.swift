//
//  LocalNetwork.swift
//  FunnyPlanner
//
//  Descoberta do endereço IPv4 da máquina na rede local, usado para montar o
//  link que os participantes abrem no navegador.
//

import Foundation

enum LocalNetwork {
    /// Retorna o endereço IPv4 da interface Wi-Fi (`en0`) da máquina, se disponível.
    /// Em caso de ausência de rede, retorna `nil`.
    static func ipv4Address() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let family = interface.ifa_addr.pointee.sa_family
            guard family == UInt8(AF_INET) else { continue }

            let name = String(cString: interface.ifa_name)
            // en0 é o Wi-Fi no macOS; preferimos ela sobre as demais.
            guard name == "en0" else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                interface.ifa_addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if result == 0 {
                address = String(cString: hostname)
                break
            }
        }
        return address
    }
}
