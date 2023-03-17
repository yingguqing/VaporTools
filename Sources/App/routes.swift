import Fluent
import Vapor

func routes(_ app: Application) throws {
    /// 主页
    app.get("index.html") { req async throws in
        try await req.view.render("index")
    }
    
    /// 重签配置界面 http://192.168.19.69:8080/upload_ipa
    app.get("ipa_resign.html") { req -> EventLoopFuture<View> in
        struct Mobileprovision: Codable {
            let mobileprovisions: [String]
        }
        let provisioningProfiles = ProvisioningProfile.getProfiles().sorted {
            ($0.name == $1.name && $0.created.timeIntervalSince1970 > $1.created.timeIntervalSince1970) || $0.name < $1.name
        }
        let mb = Mobileprovision(mobileprovisions: provisioningProfiles.map({ "\($0.name) \($0.teamID)" }))
        return req.view.render("ipa_resign", mb)
    }

    /// 上传ipa
    let uploadController = StreamController()
    /// using `body: .stream` we can get chunks of data from the client, keeping memory use low.
    app.on(.POST, "upload_ipa", body: .collect(maxSize: "2gb"), use: uploadController.upload)
    
    /// 下载重签后的ipa
    app.on(.GET, "download_ipa", use: uploadController.downloadIPA)
    
    /// 解密数据页面
    app.get("decrypt.html") { req async throws in
        try await req.view.render("decrypt")
    }
    
    /// 获取解密参数
    func getDecryptParams(req: Request) async throws -> DecryptModel {
        guard let model = try await DecryptModel.query(on: req.db).sort(.id, .descending).first() else {
            throw Abort(.notFound, reason: "解密参数不存在")
        }
        return model
    }
    
    /// 更新解密参数
    func updateDecryptParams(req: Request, json: String) async throws {
        let all = try await DecryptModel.query(on: req.db).sort(.id, .descending).all()
        for item in all {
            try await item.delete(on: req.db)
        }
        let model = DecryptModel(json: json)
        try await model.save(on: req.db)
    }
    
    /// 解密数据
    app.on(.POST, "decrypt") { req async throws -> String in
        struct Input: Content {
            let data: String
        }
        let input = try req.content.decode(Input.self)
        let model = try await getDecryptParams(req: req)
        return FlatDecrypto.decrypt(value: input.data, json: model.json)
    }
    
    /// 查看ipa信息
    app.get("ipa_preview.html") { req async throws in
        try await req.view.render("ipa_preview")
    }
    
    /// 更新解密参数的界面
    app.get("update_decrypt_keys.html") { req in
        try await req.view.render("update_decrypt_keys")
    }
    
    /// 上传更新解密参数
    app.on(.POST, "update_decrypt_params") { req async throws -> HTTPStatus in
        struct Input: Content {
            let data: String
        }
        let input = try req.content.decode(Input.self)
        try await updateDecryptParams(req: req, json: input.data)
        return .ok
    }
    
    app.get("download") { req -> EventLoopFuture<Response> in
        let path = req.query["path"] ?? ""
        guard !path.isEmpty, (DirectoryManager.share.publicDirectory / path).fileExists else {
            throw Abort(.notFound)
        }
        return req.eventLoop.makeSucceededFuture(req.fileio.streamFile(at: "Public/\(path)"))
    }
}
