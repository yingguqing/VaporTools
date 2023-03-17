//
//  WebsocketSystem.swift
//
//
//  Created by zhouziyuan on 2023/3/13.
//

import Vapor

class WebSocketSystem {
    var clients: WebSocketClients
    private var target:Any?

    init(eventLoop: EventLoop) {
        self.clients = WebSocketClients(eventLoop: eventLoop)
        target = NotificationCenter.default.addObserver(forName: .SocketSend, object: nil, queue: nil, using: { [weak self] noti in
            guard let info = noti.userInfo, let id = info["uuid"] as? String, let uuid = UUID(uuidString: id), let data = info["data"] as? Data else { return }
            let client = self?.clients.find(uuid)
            client?.send(data)
        })
    }

    func connect(_ ws: WebSocket) {
        ws.onBinary { [weak self] ws, buffer in
            guard let msg = buffer.decodeWebsocketMessage(WebSocketConnect.self) else { return }
            switch msg.data.key.lowercased() {
                case "open":
                    let client = WebSocketClient(id: msg.client, socket: ws)
                    client.createChannel(msg.data.value)
                    self?.clients.add(client)
                case "message":
                    guard let client = self?.clients.find(msg.client) else { return }
                    client.updateChannel(msg.data.value)
                case "close":
                    self?.clients.remove(msg.client)
                default:
                    print("Socket状态不存在")
            }
        }
    }
    
    deinit {
        if let target = target {
            NotificationCenter.default.removeObserver(target)
        }
    }
}
