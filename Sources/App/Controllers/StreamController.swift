import Fluent
import Vapor
import NIOCore

struct StreamController {
    let logger = Logger(label: "StreamController")
    
    /// Streaming download comes with Vapor “out of the box”.
    /// Call `req.fileio.streamFile` with a path and Vapor will generate a suitable Response.
    func downloadIPA(req: Request) async throws -> Response {
        let fileName = filename(with: req.headers)
        let filePath = DirectoryManager.share.resignDirectory / fileName
        return req.fileio.streamFile(at: filePath)
    }
    
    // MARK: The interesting bit
    /// Upload huge files (100s of gigs, even)
    /// - Problem 1: If we don’t handle the body as a stream, we’ll end up loading the entire file into memory on request.
    /// - Problem 2: Needs to scale for hundreds or thousands of concurrent transfers. So, proper memory management is crucial.
    /// - Problem 3: When *streaming* a file over HTTP (as opposed to encoding with multipart form) we need a way to know what the user’s desired filename is. So we handle a custom Header.
    /// - Problem 4: Custom headers are sometimes filtered out of network requests, so we need a fallback naming for files.
    /**
     * Example:
        curl --location --request POST 'localhost:8080/fileuploadpath' \
            --header 'Content-Type: video/mp4' \
            --header 'File-Name: bunnies-eating-strawberries.mp4' \
            --data-binary '@/Users/USERNAME/path/to/GiganticMultiGigabyteFile.mp4'
     */
    func upload(req: Request) async throws -> HTTPStatus {
        let logger = Logger(label: "StreamController.upload")
        // Create a file on disk based on our `Upload` model.
        let fileName = filename(with: req.headers)
        let filePath = DirectoryManager.share.uploadDirectory / fileName
        
        // Remove any file with the same name
        try? FileManager.default.removeItem(atPath: filePath)
        guard FileManager.default.createFile(atPath: filePath, contents: nil, attributes: nil) else {
            logger.critical("Could not upload \(fileName)")
            throw Abort(.internalServerError)
        }
        //let nioFileHandle = try NIOFileHandle(path: filePath, mode: .write, flags: .allowFileCreation(posixMode: 0x744))
        //defer { try? nioFileHandle.close() }
        do {
            var offset: Int64 = 0
            let handle = try await  req.application.fileio.openFile(path: filePath, mode: .write, flags: .allowFileCreation(posixMode: 0x744), eventLoop: req.eventLoop).get()
            //try await upload.save(on: req.db)
            for try await byteBuffer in req.body {
                do {
                    try await req.application.fileio.write(fileHandle: handle, toOffset: offset, buffer: byteBuffer, eventLoop: req.eventLoop).get()
                    offset += Int64(byteBuffer.readableBytes)
                } catch {
                    logger.error("\(error.localizedDescription)")
                }
            }
            try handle.close()
            next(file: filePath, req: req)
            return .ok
        } catch {
            try FileManager.default.removeItem(atPath: filePath)
            logger.error("File save failed for \(filePath)")
            return .internalServerError
        }
    }
    
    /// 文件上传成功后的后续
    func next(file:String, req: Request) {
        guard let next = req.headers["next-run"].first, !next.isEmpty else { return }
        switch next {
            case "resign_ipa":
                resignIpa(file: file, req: req)
            case "ipa_preview":
                ipaPreview(file: file, req: req)
            default:
                return
        }
        
    }
    
    /// ipa重签
    func resignIpa(file:String, req: Request) {
        guard let mobileprovision = req.headers["mobileprovision"].first, !mobileprovision.isEmpty, let uuid = req.headers["uuid"].first, !uuid.isEmpty else { return }
        let outputFile = DirectoryManager.share.resignDirectory / file.lastPathComponent
        let resign = ResignIPA(inputFile: file, outputFile: outputFile, provisioningFile: mobileprovision, socketUUID: uuid)
        DispatchQueue.global().async {
            resign?.startSigning()
        }
    }
    
    /// 查看ipa信息
    func ipaPreview(file:String, req:Request) {
        guard let uuid = req.headers["uuid"].first, !uuid.isEmpty else { return }
        let view = Preview(url: file.fileURL, socketUUID: uuid)
        view?.run()
    }
}
