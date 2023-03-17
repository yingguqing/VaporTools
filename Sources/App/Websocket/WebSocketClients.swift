//
//  WebsocketClients.swift
//  
//
//  Created by zhouziyuan on 2023/3/13.
//

import Vapor

open class WebSocketClients {
    var eventLoop: EventLoop
    var storage: [UUID: WebSocketClient]
    
    var active: [WebSocketClient] {
        storage.values.filter { !$0.socket.isClosed }
    }

    init(eventLoop: EventLoop, clients: [UUID: WebSocketClient] = [:]) {
        self.eventLoop = eventLoop
        self.storage = clients
    }
    
    func add(_ client: WebSocketClient) {
        storage[client.id] = client
    }

    func remove(_ client: WebSocketClient) {
        remove(client.id)
    }
    
    func remove(_ uuid:UUID) {
        storage.removeValue(forKey: uuid)
    }
    
    func find(_ uuid: UUID) -> WebSocketClient? {
        storage[uuid]
    }

    deinit {
        let futures = storage.values.map { $0.socket.close() }
        try! self.eventLoop.flatten(futures).wait()
    }
}
