//
//  FlatDecrypto.swift
//  FlatAESCrypto
//
//  Created by zhouziyuan on 2022/12/12.
//

import CryptoSwift
import Foundation

struct FlatAESCrypto {
    let aes: AES

    init(key: String, blockMode: BlockMode, padding: Padding) throws {
        self.aes = try AES(key: key.bytes, blockMode: blockMode, padding: padding)
    }

    func decrypt(_ data: Data) throws -> Data {
        let decryptedBytes = try aes.decrypt(data.bytes)
        return Data(decryptedBytes)
    }

    func encrypt(_ string: String) throws -> Data {
        let data = Data(string.utf8)
        let encryptedBytes = try aes.encrypt(data.bytes)
        return Data(encryptedBytes)
    }

    func decrypt(_ string: String) throws -> String? {
        guard let data = Data(base64Encoded: string.replacingOccurrences(of: "\n", with: "")) else { return nil }
        let deData = try decrypt(data)
        return String(data: deData, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
    }
}

extension CBC {
    init(iv: String) {
        self.init(iv: Data(iv.utf8).bytes)
    }
}

/// 解密信息
struct DecryptoInfo {
    /// 解密方法服务归属
    let name: String
    /// 默认加解密参数的索引
    let indexKey: String
    /// 是否为默认加解密参数
    var isDefault: Bool

    private let aes: FlatAESCrypto

    init(json: [String: String], key:String) {
        self.name = json["name"] ?? key
        self.indexKey = key
        self.isDefault = json["isDefault"] == "1"
        guard let mod = json["mod"]?.uppercased(), ["CBC", "ECB"].contains(mod) else {
            print("缺少参数mod，内容为解密模式。")
            exit(1)
        }
        guard let paddingString = json["padding"]?.lowercased(), ["0", "5", "7", "no"].contains(paddingString) else {
            print("\(name) 缺少参数padding，内容为解密Padding。")
            exit(1)
        }
        let iv = json["iv"] ?? ""
        let key = json["key"] ?? ""
        guard !key.isEmpty else {
            print("缺少解密key。")
            exit(1)
        }
        guard mod != "CBC" || !iv.isEmpty else {
            print("CBC模式，缺少解密iv。")
            exit(1)
        }
        let padding: Padding
        switch paddingString {
            case "0":
                padding = .zeroPadding
            case "5":
                padding = .pkcs5
            case "7":
                padding = .pkcs7
            default:
                padding = .noPadding
        }
        do {
            if mod == "CBC" {
                self.aes = try FlatAESCrypto(key: key, blockMode: CBC(iv: iv), padding: padding)
            } else {
                self.aes = try FlatAESCrypto(key: key, blockMode: ECB(), padding: padding)
            }
        } catch {
            print(error.localizedDescription)
            exit(1)
        }
    }

    /// 所有解密参数集 isOnlyOneDefault:表示随机保留一个默认解密集，用于加密
    static func all(isOnlyOneDefault: Bool = false, json:String) -> [DecryptoInfo] {
        do {
            let parsedJson = try JSONSerialization.jsonObject(with: Data(json.utf8))
            if let values = parsedJson as? [String:[String:String]] {
                var infos = values.map({ DecryptoInfo(json: $0.1, key: $0.0) })
                if isOnlyOneDefault, let item = infos.filter({  $0.isDefault }).randomElement() {
                    infos = infos.filter({ !$0.isDefault }) + [item]
                }
                return infos
            }
        } catch {
            print("\(error)")
        }
        return []
    }
    
    /// 对应的解密方法
    func flatDecrypt(value: String) -> String? {
        if isDefault {
            guard let data = Data(base64Encoded: value) else { return nil }
            let contentData = data.subdata(in: 0 ..< (data.count-1))
            let keyData = data.subdata(in: (data.count-1) ..< (data.count))
            guard let index = String(data: keyData, encoding: .utf8), indexKey == index, let dedata = try? aes.decrypt(contentData) else { return nil }
            guard let result = String(data: dedata, encoding: .utf8), !result.isEmpty else { return nil }
            return result
        } else {
            return try? aes.decrypt(value)
        }
    }

    /// 对应的加密方法
    func flatEncrypt(value: String) -> String? {
        if isDefault {
            var data = try? aes.encrypt(value)
            data?.append(Data(indexKey.utf8))
            return data?.base64EncodedString()
        } else {
            return try? aes.encrypt(value).base64EncodedString()
        }
    }
}

private extension String {
    /// 所有解密方式都解一遍
    func flatDecryptList(_ json:String) -> String? {
        // 具体的解密配置
        let infos = DecryptoInfo.all(isOnlyOneDefault: false, json: json)
        guard !self.isEmpty, !infos.isEmpty else { return nil }
        let urlDecode = self.urlDecode()
        // 优先使用配置的解密方法
        for info in infos {
            guard let result = info.flatDecrypt(value: self) ?? info.flatDecrypt(value: urlDecode) else { continue }
            return result.jsonFormat
        }
        return nil
    }
}

enum FlatDecrypto {
    static func decrypt(value: String, json:String) -> String {
        let dataString = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\\/", with: "/")
        if let deItem = dataString.flatDecryptList(json) {
            return deItem
        } else if value.isEmpty {
            return "输入加密数据"
        } else {
            return "解密失败"
        }
    }
}
