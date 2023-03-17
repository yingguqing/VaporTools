import Fluent
import FluentSQLiteDriver
import Leaf
import Vapor

// configures your application
public func configure(_ app: Application) throws {
    //app.routes.defaultMaxBodySize = "2gb"
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    app.databases.use(.sqlite(.file("db.sqlite")), as: .sqlite)
    
    app.migrations.add(CreateDecrypt())
    app.views.use(.leaf)
    try app.autoMigrate().wait()
    
    // 创建相应目录
    DirectoryManager.share.update(app: app)
    
    let socketSystem = WebSocketSystem(eventLoop: app.eventLoopGroup.next())
    app.webSocket("channel") { _, ws in
        socketSystem.connect(ws)
    }
    
    // register routes
    try routes(app)
}
