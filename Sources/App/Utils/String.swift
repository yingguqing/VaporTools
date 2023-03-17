//
//  String.swift
//
//
//  Created by zhouziyuan on 2023/3/13.
//

import Foundation

extension String {
    // 路径拼接 "/a/b" / "c.mp3" = "/a/b/c.mp3"
    static func /(parent: String, child: String) -> String {
        return (parent as NSString).appendingPathComponent(child)
    }
    
    // 字符串乘法。比如 .*2=..
    static func *(parent: String, child: Int) -> String {
        if child < 0 {
            return parent
        } else if child == 0 {
            return ""
        } else {
            let array = [String](repeating: parent, count: child)
            return array.joined()
        }
    }
    
    var fileURL: URL {
        URL(fileURLWithPath: self)
    }
    
    var lastPathComponent: String {
        return (self as NSString).lastPathComponent
    }

    var pathExtension: String {
        return (self as NSString).pathExtension
    }

    var stringByDeletingLastPathComponent: String {
        return (self as NSString).deletingLastPathComponent
    }

    var stringByDeletingPathExtension: String {
        return (self as NSString).deletingPathExtension
    }

    var pathComponents: [String] {
        return (self as NSString).pathComponents
    }
    
    func stringByAppendingPathComponent(_ path: String) -> String {
        let nsSt = self as NSString
        
        return nsSt.appendingPathComponent(path)
    }
    
    func stringByAppendingPathExtension(_ ext: String) -> String? {
        let nsSt = self as NSString
        
        return nsSt.appendingPathExtension(ext)
    }
    
    /// 文件是否存在
    var fileExists: Bool {
        return FileManager.default.fileExists(atPath: self)
    }

    /// 目录是否存在，非目录时，返回false
    var directoryExists: Bool {
        var isDirectory = ObjCBool(booleanLiteral: false)
        let isExists = FileManager.default.fileExists(atPath: self, isDirectory: &isDirectory)
        return isDirectory.boolValue && isExists
    }
    
    func pathRemove() {
        guard self.fileExists else { return }
        do {
            try FileManager.default.removeItem(atPath: self)
        } catch let error as NSError {
            print("文件删除失败 \(error.localizedDescription)")
        }
    }

    // 生成目录所有文件
    @discardableResult func createFilePath(isDelOldPath: Bool = false) -> String {
        do {
            if isDelOldPath, self.fileExists {
                self.pathRemove()
            } else if self.fileExists {
                return self
            }
            try FileManager.default.createDirectory(atPath: self, withIntermediateDirectories: true, attributes: nil)
        } catch let error as NSError {
            print("创建目录失败 \(error.localizedDescription)")
        }
        return self
    }
    
    struct StringType: OptionSet {
        let rawValue: Int
        /// 大写字母
        static let Capital = StringType(rawValue: 1)
        /// 小写字母
        static let Lower = StringType(rawValue: 2)
        /// 数字
        static let Number = StringType(rawValue: 3)
        /// 所有
        static let All: StringType = [.Capital, .Lower, .Number]
        /// 字母
        static let Letter: StringType = [.Capital, .Lower]
        
        internal init(rawValue: Int) {
            self.rawValue = rawValue
        }
        
        /// 对应可以随机的目标字符串
        var target: String {
            var randomString = ""
            if self.contains(.Capital) {
                randomString.append("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
            } else if self.contains(.Letter) {
                randomString.append("abcdefghijklmnopqrstuvwxyz")
            } else if self.contains(.Number) {
                randomString.append("1234567890")
            } else {
                assertionFailure("不存在相应的随机字符串类型")
            }
            return randomString
        }
    }
    
    /// 生成特定长度的随机字符串
    /// - Parameters:
    ///   - len: 长度
    ///   - type: 随机类型
    static func random(_ len: Int, type: StringType = .All) -> String {
        let randomString = type.target
        return String((0 ..< len).map({ _ in randomString.randomElement()! }))
    }
    
    func urlEncode() -> String {
        var allowedQueryParamAndKey = NSCharacterSet.urlQueryAllowed
        allowedQueryParamAndKey.remove(charactersIn: "!*'\"();:@&=+$,/?%#[]% ")
        return self.addingPercentEncoding(withAllowedCharacters: allowedQueryParamAndKey) ?? self
    }
    
    func urlDecode() -> String {
        return self.removingPercentEncoding ?? self
    }
    
    /// 如果是json字符串，就格式化一下，如果不是，就返回原字符串
    var jsonFormat: String {
        guard let json = try? JSONSerialization.jsonObject(with: Data(self.utf8), options: .allowFragments) else { return self }
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else { return self }
        return String(data: data, encoding: .utf8)?.replacingOccurrences(of: "\\/", with: "/") ?? self
    }
}
