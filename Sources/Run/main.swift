import App
import Vapor

// 执行命令：vapor run serve --hostname 192.168.19.69 --port 8080 --log error
// 首页：http://192.168.19.69:8080/index.html
var env = try Environment.detect()
try LoggingSystem.bootstrap(from: &env)
let app = Application(env)
defer { app.shutdown() }
try configure(app)
try app.run()
