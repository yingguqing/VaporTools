//
//  ResignIPA.swift
//
//
//  Created by zhouziyuan on 2023/3/14.
//

import Foundation
import Vapor
import Zip

class ResignIPA {
    let defaults = UserDefaults()
    let fileManager = FileManager.default
    let arPath = "/usr/bin/ar"
    let tarPath = "/usr/bin/tar"
    let unzipPath = "/usr/bin/unzip"
    let zipPath = "/usr/bin/zip"
    let defaultsPath = "/usr/bin/defaults"
    let codesignPath = "/usr/bin/codesign"
    let securityPath = "/usr/bin/security"
    let chmodPath = "/bin/chmod"
    let signableExtensions = ["dylib", "so", "0", "vis", "pvr", "framework", "appex", "app"]
    
    /// ---------------------
    /// Socket通信的uuid
    let socketUUID: String
    /// 输出目录
    let outputFile: String
    /// 描述文件名称
    var provisioningFile: String
    let inputFile: String
    var newApplicationID = ""
    var newDisplayName = ""
    var newShortVersion = ""
    var newVersion = ""
    var shouldCheckPlugins: Bool = true
    var shouldSkipGetTaskAllow: Bool = true
    lazy var logger = Logger(label: "ResignIPA.ResignIPA")
    /// 本地所有证书
    lazy var codesigningCerts: [String] = {
        var output: [String] = []
        let securityResult = Process().execute(securityPath, arguments: ["find-identity", "-v", "-p", "codesigning"])
        if securityResult.output.count < 1 {
            return output
        }
        let rawResult = securityResult.output.components(separatedBy: "\"")
        
        for index in stride(from: 0, through: rawResult.count - 2, by: 2) {
            if !(rawResult.count - 1 < index + 1) {
                output.append(rawResult[index + 1])
            }
        }
        return output.sorted()
    }()

    /// 描述文件对应的第一个证书名
    lazy var signingCertificate: String? = {
        let provisioningProfiles = ProvisioningProfile.getProfiles().sorted {
            ($0.name == $1.name && $0.created.timeIntervalSince1970 > $1.created.timeIntervalSince1970) || $0.name < $1.name
        }
        guard let profile = provisioningProfiles.filter({ provisioningFile == "\($0.name) \($0.teamID)" }).first else { return nil }
        let certficateNames = profile.certificates.map({ $0.name }).filter({ !$0.isEmpty })
        // 根据描述文件，自动切换描述文件中包含的证书，如果有多个，默认使用第一个
        guard let firstCertName = certficateNames.filter({ codesigningCerts.contains($0) }).first else { return nil }
        provisioningFile = profile.filename
        return firstCertName
    }()
    
    init?(inputFile: String, outputFile: String, provisioningFile: String, socketUUID: String) {
        self.inputFile = inputFile
        self.outputFile = outputFile
        self.provisioningFile = provisioningFile
        self.socketUUID = socketUUID
        if inputFile.pathExtension.lowercased() == "appex", inputFile != outputFile {
            setStatus("appex的输出目录要和输入目录一样")
            return nil
        } else if !inputFile.fileExists {
            return nil
        }
        Zip.addCustomFileExtension("ipa")
        try? fileManager.removeItem(atPath: outputFile)
    }
    
    func makeTempFolder() -> String? {
        return DirectoryManager.share.tempDirectory / String.random(10)
    }
    
    func setStatus(_ status: String, isSuccess: Bool = false) {
        let param:[String:Any] = [
            "msg": status,
            "isSuccess": isSuccess
        ]
        let data = param.jsonData ?? Data()
        NotificationCenter.default.post(name: .SocketSend, object: nil, userInfo: ["uuid": socketUUID, "data": data])
    }
    
    func recursiveDirectorySearch(_ path: String, extensions: [String], found: (_ file: String) -> Void) {
        if let files = try? fileManager.contentsOfDirectory(atPath: path) {
            var isDirectory: ObjCBool = true
            
            for file in files {
                let currentFile = path.stringByAppendingPathComponent(file)
                fileManager.fileExists(atPath: currentFile, isDirectory: &isDirectory)
                if isDirectory.boolValue {
                    recursiveDirectorySearch(currentFile, extensions: extensions, found: found)
                }
                if extensions.contains(file.pathExtension) {
                    if file.pathExtension != "" || file == "IpaSecurityRestriction" {
                        found(currentFile)
                    } else {
                        // NSLog("couldnt find: %@", file)
                    }
                } else if isDirectory.boolValue == false, checkMachOFile(currentFile) {
                    found(currentFile)
                }
            }
        }
    }

    func allowRecursiveSearchAt(_ path: String) -> Bool {
        return shouldCheckPlugins || path.lastPathComponent != "PlugIns"
    }
    
    /// check if Mach-O file
    func checkMachOFile(_ path: String) -> Bool {
        if let file = FileHandle(forReadingAtPath: path) {
            let data = file.readData(ofLength: 4)
            file.closeFile()
            var machOFile = data.elementsEqual([0xCE, 0xFA, 0xED, 0xFE]) || data.elementsEqual([0xCF, 0xFA, 0xED, 0xFE]) || data.elementsEqual([0xCA, 0xFE, 0xBA, 0xBE])
            
            if machOFile == false, signableExtensions.contains(path.lastPathComponent.pathExtension.lowercased()) {
                logger.info("Detected binary by extension: \(path)")
                machOFile = true
            }
            return machOFile
        }
        return false
    }
    
    func unzip(_ inputFile: String, outputPath: String) -> Bool {
        //return Process().execute(unzipPath, arguments: ["-q", inputFile, "-d", outputPath])
        do {
            try Zip.unzipFile(inputFile.fileURL, destination: outputPath.fileURL, overwrite: true, password: nil)
            return true
        } catch {
            logger.error("unzip faild:\(error)")
            return false
        }
    }

    func zip(_ inputPath: String, outputFile: String) -> AppSignerTaskOutput {
        return Process().execute(zipPath, workingDirectory: inputPath, arguments: ["-qry", outputFile, "."])
    }
    
    func cleanup(_ tempFolder: String) {
        do {
            logger.info("Deleting: \(tempFolder)")
            try fileManager.removeItem(atPath: tempFolder)
            try fileManager.removeItem(atPath: inputFile)
        } catch let error as NSError {
            setStatus("Unable to delete temp folder")
            logger.error("\(error.localizedDescription)")
        }
    }

    func bytesToSmallestSi(_ size: Double) -> String {
        let prefixes = ["", "K", "M", "G", "T", "P", "E", "Z", "Y"]
        for i in 1 ... 6 {
            let nextUnit = pow(1024.00, Double(i + 1))
            let unitMax = pow(1024.00, Double(i))
            if size < nextUnit {
                return "\(round((size / unitMax) * 100) / 100)\(prefixes[i])B"
            }
        }
        return "\(size)B"
    }

    func getPlistKey(_ plist: String, keyName: String) -> String? {
        let dictionary = NSDictionary(contentsOfFile: plist)
        return dictionary?[keyName] as? String
    }
    
    func setPlistKey(_ plist: String, keyName: String, value: String) -> AppSignerTaskOutput {
        return Process().execute(defaultsPath, arguments: ["write", plist, keyName, value])
    }
    
    // MARK: Codesigning
    @discardableResult
    func codeSign(_ file: String, certificate: String, entitlements: String?, before: ((_ file: String, _ certificate: String, _ entitlements: String?) -> Void)?, after: ((_ file: String, _ certificate: String, _ entitlements: String?, _ codesignTask: AppSignerTaskOutput) -> Void)?) -> AppSignerTaskOutput {
        var needEntitlements = false
        let filePath: String
        switch file.pathExtension.lowercased() {
        case "framework":
            // append executable file in framework
            let fileName = file.lastPathComponent.stringByDeletingPathExtension
            filePath = file.stringByAppendingPathComponent(fileName)
        case "app", "appex":
            // read executable file from Info.plist
            let infoPlist = file.stringByAppendingPathComponent("Info.plist")
            let executableFile = getPlistKey(infoPlist, keyName: "CFBundleExecutable")!
            filePath = file.stringByAppendingPathComponent(executableFile)

            if let entitlementsPath = entitlements, fileManager.fileExists(atPath: entitlementsPath) {
                needEntitlements = true
            }
        default:
            filePath = file
        }

        if let beforeFunc = before {
            beforeFunc(file, certificate, entitlements)
        }

        var arguments = ["-f", "-s", certificate, "--generate-entitlement-der"]
        if needEntitlements {
            arguments += ["--entitlements", entitlements!]
        }
        arguments.append(filePath)

        let codesignTask = Process().execute(codesignPath, arguments: arguments)
        if codesignTask.status != 0 {
            logger.info("Error codesign: \(codesignTask.output)")
        }
        
        if let afterFunc = after {
            afterFunc(file, certificate, entitlements, codesignTask)
        }
        return codesignTask
    }
    
    func startSigning() {
        // MARK: Set up variables
        var eggCount = 0
        
        // Check signing certificate selection
        if signingCertificate == nil {
            setStatus("No signing certificate selected")
            return
        }
        
        // Check if input file exists
        // MARK: Create working temp folder
        var tempFolder: String!
        if let tmpFolder = makeTempFolder() {
            tempFolder = tmpFolder
        } else {
            setStatus("Error creating temp folder")
            return
        }
        let workingDirectory = tempFolder.stringByAppendingPathComponent("out")
        workingDirectory.createFilePath()
        let eggDirectory = tempFolder.stringByAppendingPathComponent("eggs")
        let payloadDirectory = workingDirectory.stringByAppendingPathComponent("Payload/")
        let entitlementsPlist = tempFolder.stringByAppendingPathComponent("entitlements.plist")
        
        logger.info("Temp folder: \(String(describing: tempFolder))")
        logger.info("Working directory: \(workingDirectory)")
        logger.info("Payload directory: \(payloadDirectory)")
        
        // MARK: Create Egg Temp Directory
        do {
            try fileManager.createDirectory(atPath: eggDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch let error as NSError {
            setStatus("Error creating egg temp directory")
            logger.error("\(error.localizedDescription)")
            cleanup(tempFolder)
            return
        }
        
        // MARK: Process input file
        switch inputFile.pathExtension.lowercased() {
        case "deb":
            // MARK: - -Unpack deb
            let debPath = tempFolder.stringByAppendingPathComponent("deb")
            do {
                try fileManager.createDirectory(atPath: debPath, withIntermediateDirectories: true, attributes: nil)
                try fileManager.createDirectory(atPath: workingDirectory, withIntermediateDirectories: true, attributes: nil)
                setStatus("Extracting deb file")
                let debTask = Process().execute(arPath, workingDirectory: debPath, arguments: ["-x", inputFile])
                logger.info("\(debTask.output)")
                if debTask.status != 0 {
                    setStatus("Error processing deb file")
                    cleanup(tempFolder)
                    return
                }
                
                var tarUnpacked = false
                for tarFormat in ["tar", "tar.gz", "tar.bz2", "tar.lzma", "tar.xz"] {
                    let dataPath = debPath.stringByAppendingPathComponent("data.\(tarFormat)")
                    if fileManager.fileExists(atPath: dataPath) {
                        setStatus("Unpacking data.\(tarFormat)")
                        let tarTask = Process().execute(tarPath, workingDirectory: debPath, arguments: ["-xf", dataPath])
                        logger.info("\(tarTask.output)")
                        if tarTask.status == 0 {
                            tarUnpacked = true
                        }
                        break
                    }
                }
                if !tarUnpacked {
                    setStatus("Error unpacking data.tar")
                    cleanup(tempFolder)
                    return
                }
              
                var sourcePath = debPath.stringByAppendingPathComponent("Applications")
                if fileManager.fileExists(atPath: debPath.stringByAppendingPathComponent("var/mobile/Applications")) {
                    sourcePath = debPath.stringByAppendingPathComponent("var/mobile/Applications")
                }
              
                try fileManager.moveItem(atPath: sourcePath, toPath: payloadDirectory)
                
            } catch {
                setStatus("Error processing deb file")
                cleanup(tempFolder)
                return
            }
            
        case "ipa":
            // MARK: - -Unzip ipa
            do {
                try fileManager.createDirectory(atPath: workingDirectory, withIntermediateDirectories: true, attributes: nil)
                setStatus("Extracting ipa file")
                
                let unzipTask = self.unzip(inputFile, outputPath: workingDirectory)
                if !unzipTask {
                    setStatus("Error extracting ipa file")
                    cleanup(tempFolder)
                    return
                }
            } catch {
                setStatus("Error extracting ipa file")
                cleanup(tempFolder)
                return
            }
            
        case "app", "appex":
            // MARK: - -Copy app bundle
            do {
                try fileManager.createDirectory(atPath: payloadDirectory, withIntermediateDirectories: true, attributes: nil)
                setStatus("Copying app to payload directory")
                try fileManager.copyItem(atPath: inputFile, toPath: payloadDirectory.stringByAppendingPathComponent(inputFile.lastPathComponent))
            } catch {
                setStatus("Error copying app to payload directory")
                cleanup(tempFolder)
                return
            }
            
        case "xcarchive":
            // MARK: - -Copy app bundle from xcarchive
            do {
                try fileManager.createDirectory(atPath: workingDirectory, withIntermediateDirectories: true, attributes: nil)
                setStatus("Copying app to payload directory")
                try fileManager.copyItem(atPath: inputFile.stringByAppendingPathComponent("Products/Applications/"), toPath: payloadDirectory)
            } catch {
                setStatus("Error copying app to payload directory")
                cleanup(tempFolder)
                return
            }
            
        default:
            setStatus("Unsupported input file")
            cleanup(tempFolder)
            return
        }
        
        if !fileManager.fileExists(atPath: payloadDirectory) {
            setStatus("Payload directory doesn't exist")
            cleanup(tempFolder)
            return
        }
        
        // Loop through app bundles in payload directory
        do {
            let files = try fileManager.contentsOfDirectory(atPath: payloadDirectory)
            var isDirectory: ObjCBool = true
            
            for file in files {
                fileManager.fileExists(atPath: payloadDirectory.stringByAppendingPathComponent(file), isDirectory: &isDirectory)
                if !isDirectory.boolValue { continue }
                
                // MARK: Bundle variables setup
                let appBundlePath = payloadDirectory.stringByAppendingPathComponent(file)
                let appBundleInfoPlist = appBundlePath.stringByAppendingPathComponent("Info.plist")
                let appBundleProvisioningFilePath = appBundlePath.stringByAppendingPathComponent("embedded.mobileprovision")
                let useAppBundleProfile = (provisioningFile.isEmpty && fileManager.fileExists(atPath: appBundleProvisioningFilePath))
                
                // MARK: Delete CFBundleResourceSpecification from Info.plist
                let out = Process().execute(defaultsPath, arguments: ["delete", appBundleInfoPlist, "CFBundleResourceSpecification"]).output
                logger.info("\(out)")
                
                // MARK: Copy Provisioning Profile
                if !provisioningFile.isEmpty {
                    if fileManager.fileExists(atPath: appBundleProvisioningFilePath) {
                        setStatus("Deleting embedded.mobileprovision")
                        do {
                            try fileManager.removeItem(atPath: appBundleProvisioningFilePath)
                        } catch let error as NSError {
                            setStatus("Error deleting embedded.mobileprovision")
                            logger.error("\(error.localizedDescription)")
                            cleanup(tempFolder)
                            return
                        }
                    }
                    setStatus("Copying provisioning profile to app bundle")
                    do {
                        try fileManager.copyItem(atPath: provisioningFile, toPath: appBundleProvisioningFilePath)
                    } catch let error as NSError {
                        setStatus("Error copying provisioning profile")
                        logger.error("\(error.localizedDescription)")
                        cleanup(tempFolder)
                        return
                    }
                }
                
                let bundleID = getPlistKey(appBundleInfoPlist, keyName: "CFBundleIdentifier")
                
                // MARK: Generate entitlements.plist
                if !provisioningFile.isEmpty || useAppBundleProfile {
                    setStatus("Parsing entitlements")
                    
                    if var profile = ProvisioningProfile(filename: useAppBundleProfile ? appBundleProvisioningFilePath : provisioningFile) {
                        if shouldSkipGetTaskAllow {
                            profile.removeGetTaskAllow()
                        }
                        let isWildcard = profile.appID == "*" // TODO: support com.example.* wildcard
                        if !isWildcard, newApplicationID != "", newApplicationID != profile.appID {
                            setStatus("Unable to change App ID to \(newApplicationID), provisioning profile won't allow it")
                            cleanup(tempFolder)
                            return
                        } else if isWildcard {
                            if newApplicationID != "" {
                                profile.update(trueAppID: newApplicationID)
                            } else if let existingBundleID = bundleID {
                                profile.update(trueAppID: existingBundleID)
                            }
                        }
                        if let entitlements = profile.getEntitlementsPlist() {
                            logger.info("–––––––––––––––––––––––\n\(entitlements)")
                            logger.info("–––––––––––––––––––––––")
                            do {
                                try entitlements.write(toFile: entitlementsPlist, atomically: false, encoding: .utf8)
                                setStatus("Saved entitlements to \(entitlementsPlist)")
                            } catch let error as NSError {
                                setStatus("Error writing entitlements.plist, \(error.localizedDescription)")
                            }
                        } else {
                            setStatus("Unable to read entitlements from provisioning profile")
                        }
                    } else {
                        setStatus("Unable to parse provisioning profile, it may be corrupt")
                    }
                }
                
                // MARK: Make sure that the executable is well... executable.
                if let bundleExecutable = getPlistKey(appBundleInfoPlist, keyName: "CFBundleExecutable") {
                    _ = Process().execute(chmodPath, arguments: ["755", appBundlePath.stringByAppendingPathComponent(bundleExecutable)])
                }
                
                // MARK: Change Application ID
                if newApplicationID != "" {
                    if let oldAppID = bundleID {
                        func changeAppexID(_ appexFile: String) {
                            guard allowRecursiveSearchAt(appexFile.stringByDeletingLastPathComponent) else {
                                return
                            }

                            let appexPlist = appexFile.stringByAppendingPathComponent("Info.plist")
                            if let appexBundleID = getPlistKey(appexPlist, keyName: "CFBundleIdentifier") {
                                let newAppexID = "\(newApplicationID)\(String(appexBundleID[oldAppID.endIndex...]))"
                                setStatus("Changing \(appexFile) id to \(newAppexID)")
                                _ = setPlistKey(appexPlist, keyName: "CFBundleIdentifier", value: newAppexID)
                            }
                            if Process().execute(defaultsPath, arguments: ["read", appexPlist, "WKCompanionAppBundleIdentifier"]).status == 0 {
                                _ = setPlistKey(appexPlist, keyName: "WKCompanionAppBundleIdentifier", value: newApplicationID)
                            }
                            // 修复微信改bundleid后安装失败问题
                            let pluginInfoPlist = NSMutableDictionary(contentsOfFile: appexPlist)
                            if let dictionaryArray = pluginInfoPlist?["NSExtension"] as? [String: AnyObject],
                               let attributes: NSMutableDictionary = dictionaryArray["NSExtensionAttributes"] as? NSMutableDictionary,
                               let wkAppBundleIdentifier = attributes["WKAppBundleIdentifier"] as? String
                            {
                                let newAppesID = wkAppBundleIdentifier.replacingOccurrences(of: oldAppID, with: newApplicationID)
                                attributes["WKAppBundleIdentifier"] = newAppesID
                                pluginInfoPlist!.write(toFile: appexPlist, atomically: true)
                            }
                            recursiveDirectorySearch(appexFile, extensions: ["app"], found: changeAppexID)
                        }
                        recursiveDirectorySearch(appBundlePath, extensions: ["appex"], found: changeAppexID)
                    }
                    
                    setStatus("Changing App ID to \(newApplicationID)")
                    let IDChangeTask = setPlistKey(appBundleInfoPlist, keyName: "CFBundleIdentifier", value: newApplicationID)
                    if IDChangeTask.status != 0 {
                        setStatus("Error changing App ID")
                        logger.error("\(IDChangeTask.output)")
                        cleanup(tempFolder)
                        return
                    }
                }
                
                // MARK: Change Display Name
                if newDisplayName != "" {
                    setStatus("Changing Display Name to \(newDisplayName))")
                    let displayNameChangeTask = Process().execute(defaultsPath, arguments: ["write", appBundleInfoPlist, "CFBundleDisplayName", newDisplayName])
                    if displayNameChangeTask.status != 0 {
                        setStatus("Error changing display name")
                        logger.error("\(displayNameChangeTask.output)")
                        cleanup(tempFolder)
                        return
                    }
                }
                
                // MARK: Change Version
                if newVersion != "" {
                    setStatus("Changing Version to \(newVersion)")
                    let versionChangeTask = Process().execute(defaultsPath, arguments: ["write", appBundleInfoPlist, "CFBundleVersion", newVersion])
                    if versionChangeTask.status != 0 {
                        setStatus("Error changing version")
                        logger.error("\(versionChangeTask.output)")
                        cleanup(tempFolder)
                        return
                    }
                }
                
                // MARK: Change Short Version
                if newShortVersion != "" {
                    setStatus("Changing Short Version to \(newShortVersion)")
                    let shortVersionChangeTask = Process().execute(defaultsPath, arguments: ["write", appBundleInfoPlist, "CFBundleShortVersionString", newShortVersion])
                    if shortVersionChangeTask.status != 0 {
                        setStatus("Error changing short version")
                        logger.error("\(shortVersionChangeTask.output)")
                        cleanup(tempFolder)
                        return
                    }
                }
                
                func generateFileSignFunc(_ payloadDirectory: String, entitlementsPath: String, signingCertificate: String) -> ((_ file: String) -> Void) {
                    let useEntitlements: Bool = {
                        if fileManager.fileExists(atPath: entitlementsPath) {
                            return true
                        }
                        return false
                    }()
                    
                    func shortName(_ file: String, payloadDirectory: String) -> String {
                        return String(file[payloadDirectory.endIndex...])
                    }
                    
                    func beforeFunc(_ file: String, certificate: String, entitlements: String?) {
                        setStatus("Codesigning \(shortName(file, payloadDirectory: payloadDirectory))\(useEntitlements ? " with entitlements" : "")")
                    }
                    
                    func afterFunc(_ file: String, certificate: String, entitlements: String?, codesignOutput: AppSignerTaskOutput) {
                        if codesignOutput.status != 0 {
                            setStatus("Error codesigning \(shortName(file, payloadDirectory: payloadDirectory))")
                            logger.error("\(codesignOutput.output)")
                        }
                    }
                    
                    func output(_ file: String) {
                        codeSign(file, certificate: signingCertificate, entitlements: entitlementsPath, before: beforeFunc, after: afterFunc)
                    }
                    return output
                }
                
                // MARK: Codesigning - Eggs
                let eggSigningFunction = generateFileSignFunc(eggDirectory, entitlementsPath: entitlementsPlist, signingCertificate: signingCertificate!)
                func signEgg(_ eggFile: String) {
                    eggCount += 1
                    
                    let currentEggPath = eggDirectory.stringByAppendingPathComponent("egg\(eggCount)")
                    currentEggPath.createFilePath()
                    let shortName = String(eggFile[payloadDirectory.endIndex...])
                    setStatus("Extracting \(shortName)")
                    if !self.unzip(eggFile, outputPath: currentEggPath) {
                        logger.error("Error extracting \(shortName)")
                        return
                    }
                    recursiveDirectorySearch(currentEggPath, extensions: ["egg"], found: signEgg)
                    recursiveDirectorySearch(currentEggPath, extensions: signableExtensions, found: eggSigningFunction)
                    setStatus("Compressing \(shortName)")
                    _ = self.zip(currentEggPath, outputFile: eggFile)
                }
                
                recursiveDirectorySearch(appBundlePath, extensions: ["egg"], found: signEgg)
                
                // MARK: Codesigning - App
                let signingFunction = generateFileSignFunc(payloadDirectory, entitlementsPath: entitlementsPlist, signingCertificate: signingCertificate!)
                
                recursiveDirectorySearch(appBundlePath, extensions: signableExtensions, found: signingFunction)
                signingFunction(appBundlePath)
                
                // MARK: Codesigning - Verification
                let verificationTask = Process().execute(codesignPath, arguments: ["-v", appBundlePath])
                if verificationTask.status != 0 {
                    setStatus("Error verifying code signature")
                    logger.error("\(verificationTask.output)")
                    cleanup(tempFolder)
                }
            }
        } catch let error as NSError {
            setStatus("Error listing files in payload directory")
            logger.error("\(error.localizedDescription)")
            cleanup(tempFolder)
            return
        }
        
        // MARK: Packaging
        // Check if output already exists and delete if so
        if fileManager.fileExists(atPath: outputFile) {
            do {
                try fileManager.removeItem(atPath: outputFile)
            } catch let error as NSError {
                setStatus("Error deleting output file")
                logger.error("\(error.localizedDescription)")
                cleanup(tempFolder)
                return
            }
        }

        switch outputFile.pathExtension.lowercased() {
        case "ipa":
            setStatus("Packaging IPA")
            let zipTask = self.zip(workingDirectory, outputFile: outputFile)
            if zipTask.status != 0 {
                setStatus("Error packaging IPA")
            }
        case "appex":
            do {
                try fileManager.copyItem(atPath: payloadDirectory.stringByAppendingPathComponent(inputFile.lastPathComponent), toPath: outputFile)
            } catch let error as NSError {
                setStatus("Error copying appex bundle to \(outputFile)")
                logger.error("\(error.localizedDescription)")
            }
        default:
            break
        }

        // MARK: Cleanup
        cleanup(tempFolder)
        setStatus("重签成功，请下载")
        setStatus(DirectoryManager.share.remove(type: .Public, from: outputFile), isSuccess: true)
    }
}
