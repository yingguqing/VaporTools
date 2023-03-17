//
//  WebSocketClient.swift
//
//
//  Created by zhouziyuan on 2023/3/13.
//

import Vapor

protocol WebSocketChannelUpdate {
    var socket: WebSocket { get }
    func update(data: String)
}

class WebSocketClient {
    let id: UUID
    let socket: WebSocket
    private var channel: WebSocketChannelUpdate?

    init(id: UUID, socket: WebSocket) {
        self.id = id
        self.socket = socket
    }

    func createChannel(_ data: String) {
        guard channel == nil else {
            print("Socket更新渠道已存在")
            return
        }
        switch data.lowercased() {
            case "resign_ipa", "ipa_preview":
                channel = nil
            default:
                print("Socket渠道标识不存在：\(data)")
        }
    }

    func updateChannel(_ data: String) {
        channel?.update(data: data)
    }
    
    func send(_ data:Data) {
        socket.send([UInt8](data))
    }
}
