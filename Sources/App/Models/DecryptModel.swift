//
//  FlatDecryptoInfo.swift
//  
//
//  Created by zhouziyuan on 2023/3/16.
//

import Fluent
import Vapor


final class DecryptModel: Model, Content, CustomStringConvertible {
    init() { }
    
    static let schema = "flat_decrypt"
    
    @ID(key: .id)
    var id: UUID?
    
    /// 所有加密参数
    @Field(key: "json")
    var json:String
    
    
    init(id:UUID? = nil, json:String) {
        self.id = id
        self.json = json
    }
}


