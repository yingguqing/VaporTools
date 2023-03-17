//
//  DirectoryManager.swift
//  
//
//  Created by zhouziyuan on 2023/3/16.
//

import Foundation
import Vapor

class DirectoryManager {
    static let share = DirectoryManager()
    
    enum DirectoryType {
        case Work
        case Public
        case Temp
        case Upload
        case Resign
        case Resources
        
        var path:String {
            let share = DirectoryManager.share
            switch self {
                case .Work:
                    return share.workingDirectory
                case .Public:
                    return share.publicDirectory
                case .Temp:
                    return share.tempDirectory
                case .Upload:
                    return share.uploadDirectory
                case .Resign:
                    return share.resignDirectory
                case .Resources:
                    return share.resourcesDirectory
            }
        }
    }
    
    /// 工作目录
    private(set) var workingDirectory:String = ""
    /// 公开目录
    private(set) var publicDirectory:String = ""
    /// 临时目录
    private(set) var tempDirectory:String = ""
    /// 上传目录
    private(set) var uploadDirectory:String = ""
    /// 重签名文件保存目录
    private(set) var resignDirectory:String = ""
    /// 资源目录
    private(set) var resourcesDirectory:String = ""
    
    func update(app: Application) {
        workingDirectory = app.directory.workingDirectory
        publicDirectory = app.directory.publicDirectory
        resourcesDirectory = app.directory.workingDirectory / "Resources"
        configureUploadDirectory(named: "Uploads", for: app).whenSuccess { [weak self] path in
            self?.uploadDirectory = path
        }
        configureUploadDirectory(named: "Resign", for: app).whenSuccess { [weak self] path in
            self?.resignDirectory = path
        }
        configureUploadDirectory(named: "temp", for: app).whenSuccess { [weak self] path in
            self?.tempDirectory = path
        }
    }
    
    /// 从路径中移除特定目录
    func remove(type:DirectoryType, from path:String) -> String {
        return path.replacingOccurrences(of: type.path, with: "")
    }
}
