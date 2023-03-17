//
//  Dictionary.swift
//
//
//  Created by zhouziyuan on 2023/3/15.
//

import Foundation

protocol JsonKey {
    var key: String { get }
}

extension String: JsonKey {
    var key: String {
        return self
    }
}

extension Dictionary where Key == String {
    var jsonData: Data? {
        return try? JSONSerialization.data(withJSONObject: self, options: [.sortedKeys, .prettyPrinted])
    }

    var jsonString: String? {
        guard let data = self.jsonData else { return nil }
        return String(data: data, encoding: .utf8)?.replacingOccurrences(of: "\\/", with: "/")
    }

    func value<T>(key: JsonKey) -> T? {
        guard let value = self[key.key] else { return nil }
        if T.self == Int.self {
            var result: Int?
            if let val = value as? Int {
                result = val
            } else if let val = value as? String {
                result = Int(val)
            } else if let val = value as? Double {
                result = Int(val)
            } else if let val = value as? Bool {
                result = (val ? 1 : 0)
            }
            return result as? T
        } else if T.self == String.self {
            var result: String?
            if let val = value as? Int {
                result = String(val)
            } else if let val = value as? String {
                result = val
            } else if let val = value as? Double {
                result = String(val)
            } else if let val = value as? Bool {
                result = (val ? "true" : "false")
            }
            return result as? T
        } else if T.self == Bool.self {
            var result: Bool?
            if let val = value as? Int {
                result = val != 0
            } else if let val = value as? String {
                let low = val.lowercased()
                if low == "true" || low == "1" {
                    result = true
                } else if low == "false" || low == "0" {
                    result = false
                } else {
                    result = !val.isEmpty
                }
            } else if let val = value as? Double {
                result = val != 0
            } else if let val = value as? Bool {
                result = val
            }
            return result as? T
        } else if T.self == Double.self {
            var result: Double?
            if let val = value as? Int {
                result = Double(val)
            } else if let val = value as? String {
                result = Double(val)
            } else if let val = value as? Double {
                result = val
            } else if let val = value as? Bool {
                result = Double(val ? 1 : 0)
            }
            return result as? T
        } else {
            return value as? T
        }
    }
}
