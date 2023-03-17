//
//  CreateDecrypt.swift
//  
//
//  Created by zhouziyuan on 2023/3/16.
//

import Fluent

struct CreateDecrypt: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        return database.schema(DecryptModel.schema)
            .id()
            .field("json", .string, .required)
            .create()
    }
    
    func revert(on database: Database) -> EventLoopFuture<Void> {
        return database.schema(DecryptModel.schema).delete()
    }
    
    
}
