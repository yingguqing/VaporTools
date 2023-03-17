//
//  WebsocketMessage.swift
//  
//
//  Created by zhouziyuan on 2023/3/13.
//

import Vapor

struct WebSocketMessage<T: Codable>: Codable {
    let client: UUID
    let data: T
}

extension ByteBuffer {
    func decodeWebsocketMessage<T: Codable>(_ type: T.Type) -> WebSocketMessage<T>? {
        try? JSONDecoder().decode(WebSocketMessage<T>.self, from: self)
    }
}

