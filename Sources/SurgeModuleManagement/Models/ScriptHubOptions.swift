import Foundation

/// Script-Hub 重写转换器支持的 Surge 目标参数。
/// 字段名刻意贴近上游参数，便于随 Script-Hub 更新时核对兼容性。
struct ScriptHubOptions: Codable, Hashable, Sendable {
    var scriptConversionKeywords = ""
    var convertAllScripts = false
    var responseScriptConversionKeywords = ""
    var convertAllResponseScripts = false
    var compatibilityOnly = false
    var prependScript = ""
    var scriptEvalOriginal = ""
    var scriptEvalConverted = ""
    var scriptEvalOriginalURL = ""
    var scriptEvalConvertedURL = ""

    var includeKeywords = ""
    var excludeKeywords = ""
    var syncMITMToForceHTTP = false
    var removeCommentedRewrites = true
    var keepMapLocalHeaders = false
    var useJSDelivr = false

    var policy = ""
    var mitmAdd = ""
    var mitmRemove = ""
    var mitmRemoveRegex = ""
    var scriptNameTargets = ""
    var scriptNames = ""
    var timeoutTargets = ""
    var timeoutValues = ""
    var engineTargets = ""
    var engineValues = ""
    var cronTargets = ""
    var cronExpressions = ""
    var argumentTargets = ""
    var argumentValues = ""

    var noResolve = false
    var sniKeywords = ""
    var preMatchingKeywords = ""
    var enableJQ = true
    var requestHeaders = ""
    var evalOriginal = ""
    var evalConverted = ""
    var evalOriginalURL = ""
    var evalConvertedURL = ""

    init() {}

    init(query: [String: String]) {
        self.init()
        scriptConversionKeywords = query["jsc"] == "." ? "" : query["jsc", default: ""]
        convertAllScripts = query["jsc"] == "."
        responseScriptConversionKeywords = query["jsc2"] == "." ? "" : query["jsc2", default: ""]
        convertAllResponseScripts = query["jsc2"] == "."
        compatibilityOnly = Self.bool(query["compatibilityOnly"])
        prependScript = query["prepend", default: ""]
        scriptEvalOriginal = query["evJsori", default: ""]
        scriptEvalConverted = query["evJsmodi", default: ""]
        scriptEvalOriginalURL = query["evUrlori", default: ""]
        scriptEvalConvertedURL = query["evUrlmodi", default: ""]
        includeKeywords = query["y", default: ""]
        excludeKeywords = query["x", default: ""]
        syncMITMToForceHTTP = Self.bool(query["synMitm"])
        if let value = query["del"] { removeCommentedRewrites = Self.bool(value) }
        keepMapLocalHeaders = Self.bool(query["keepHeader"])
        useJSDelivr = Self.bool(query["jsDelivr"])
        policy = query["policy", default: ""]
        mitmAdd = query["hnadd", default: ""]
        mitmRemove = query["hndel", default: ""]
        mitmRemoveRegex = query["hnregdel", default: ""]
        scriptNameTargets = query["njsnametarget", default: ""]
        scriptNames = query["njsname", default: ""]
        timeoutTargets = query["timeoutt", default: ""]
        timeoutValues = query["timeoutv", default: ""]
        engineTargets = query["enginet", default: ""]
        engineValues = query["enginev", default: ""]
        cronTargets = query["cron", default: ""]
        cronExpressions = query["cronexp", default: ""]
        argumentTargets = query["arg", default: ""]
        argumentValues = query["argv", default: ""]
        noResolve = Self.bool(query["nore"])
        sniKeywords = query["sni", default: ""]
        preMatchingKeywords = query["pm", default: ""]
        if let value = query["jqEnabled"] { enableJQ = Self.bool(value) }
        requestHeaders = query["headers", default: ""]
        evalOriginal = query["evalScriptori", default: ""]
        evalConverted = query["evalScriptmodi", default: ""]
        evalOriginalURL = query["evalUrlori", default: ""]
        evalConvertedURL = query["evalUrlmodi", default: ""]
    }

    func queryItems() -> [URLQueryItem] {
        var values: [(String, String)] = [
            ("del", String(removeCommentedRewrites)),
            ("jqEnabled", String(enableJQ)),
            ("noNtf", "true")
        ]

        func add(_ name: String, _ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { values.append((name, value)) }
        }
        func add(_ name: String, _ value: Bool) {
            if value { values.append((name, "true")) }
        }

        add("jsc", convertAllScripts ? "." : scriptConversionKeywords)
        add("jsc2", convertAllResponseScripts ? "." : responseScriptConversionKeywords)
        add("compatibilityOnly", compatibilityOnly)
        add("prepend", prependScript)
        add("evJsori", scriptEvalOriginal)
        add("evJsmodi", scriptEvalConverted)
        add("evUrlori", scriptEvalOriginalURL)
        add("evUrlmodi", scriptEvalConvertedURL)
        add("y", includeKeywords)
        add("x", excludeKeywords)
        add("synMitm", syncMITMToForceHTTP)
        add("keepHeader", keepMapLocalHeaders)
        add("jsDelivr", useJSDelivr)
        add("policy", policy)
        add("hnadd", mitmAdd)
        add("hndel", mitmRemove)
        add("hnregdel", mitmRemoveRegex)
        add("njsnametarget", scriptNameTargets)
        add("njsname", scriptNames)
        add("timeoutt", timeoutTargets)
        add("timeoutv", timeoutValues)
        add("enginet", engineTargets)
        add("enginev", engineValues)
        add("cron", cronTargets)
        add("cronexp", cronExpressions)
        add("arg", argumentTargets)
        add("argv", argumentValues)
        add("nore", noResolve)
        add("sni", sniKeywords)
        add("pm", preMatchingKeywords)
        add("headers", requestHeaders)
        add("evalScriptori", evalOriginal)
        add("evalScriptmodi", evalConverted)
        add("evalUrlori", evalOriginalURL)
        add("evalUrlmodi", evalConvertedURL)
        return values.map { URLQueryItem(name: $0.0, value: $0.1) }
    }

    var configuredSummary: String? {
        var items: [String] = []

        func add(_ label: String, _ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { items.append("\(label)：\(trimmed)") }
        }
        func add(_ label: String, when enabled: Bool) {
            if enabled { items.append(label) }
        }

        add("脚本转换", convertAllScripts ? "全部" : scriptConversionKeywords)
        add("响应脚本转换", convertAllResponseScripts ? "全部" : responseScriptConversionKeywords)
        add("仅兼容转换", when: compatibilityOnly)
        add("脚本前置代码", prependScript)
        add("原脚本处理", scriptEvalOriginal)
        add("转换脚本处理", scriptEvalConverted)
        add("原脚本处理 URL", scriptEvalOriginalURL)
        add("转换脚本处理 URL", scriptEvalConvertedURL)
        add("仅保留", includeKeywords)
        add("排除", excludeKeywords)
        add("MitM 同步 Force HTTP", when: syncMITMToForceHTTP)
        add("保留注释重写", when: !removeCommentedRewrites)
        add("保留 Map Local 请求头", when: keepMapLocalHeaders)
        add("使用 jsDelivr", when: useJSDelivr)
        add("策略", policy)
        add("添加 MitM", mitmAdd)
        add("移除 MitM", mitmRemove)
        add("正则移除 MitM", mitmRemoveRegex)
        add("脚本名目标", scriptNameTargets)
        add("脚本名", scriptNames)
        add("超时目标", timeoutTargets)
        add("超时值", timeoutValues)
        add("引擎目标", engineTargets)
        add("引擎值", engineValues)
        add("定时任务目标", cronTargets)
        add("定时表达式", cronExpressions)
        add("参数目标", argumentTargets)
        add("参数值", argumentValues)
        add("禁用 DNS 解析", when: noResolve)
        add("SNI 关键字", sniKeywords)
        add("预匹配关键字", preMatchingKeywords)
        add("关闭 jq", when: !enableJQ)
        add("请求头", requestHeaders)
        add("原内容处理", evalOriginal)
        add("转换内容处理", evalConverted)
        add("原内容处理 URL", evalOriginalURL)
        add("转换内容处理 URL", evalConvertedURL)
        return items.isEmpty ? nil : items.joined(separator: " · ")
    }

    private static func bool(_ value: String?) -> Bool {
        guard let value else { return false }
        return ["true", "1", "yes", "on"].contains(value.lowercased())
    }
}
