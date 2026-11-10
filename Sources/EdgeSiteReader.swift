import AppKit

final class EdgeSiteReader {
    private let queue=DispatchQueue(label:"local.radishnotes.edge-reading",qos:.utility)
    private var busy=false
    // Fixed, read-only Apple Event script; no URL or website content is executed as code.
    func read(completion:@escaping(String?,String?)->Void) {
        guard !busy else { return };busy=true
        queue.async {
            let source="""
            with timeout of 5 seconds
                tell application id "com.microsoft.edgemac"
                    if (count of windows) is 0 then return ""
                    return URL of active tab of front window
                end tell
            end timeout
            """
            var error:NSDictionary?
            let result=NSAppleScript(source:source)?.executeAndReturnError(&error)
            let raw=result?.stringValue
            let code=error?[NSAppleScript.errorNumber] as? Int
            if let folder=RuntimeEvidence.folder {
                let record:[String:Any] = ["errorCode":code ?? 0,"time":Date().timeIntervalSince1970]
                if let data=try? JSONSerialization.data(withJSONObject:record) {try? data.write(to:folder.appendingPathComponent("edge-read-status.json"))}
            }
            let message:String?
            if code == -1743 { message="Edge 未授权，暂不判断网页。可在系统设置 → 隐私与安全性 → 自动化中允许萝卜便签。" }
            else if error != nil { message="暂时无法读取 Edge 网站（错误 \(code ?? 0)），不作分心判断。" }
            else if raw?.isEmpty != false { message="Edge 没有可识别的网页。" }
            else { message=nil }
            // Reduce to hostname on the worker; never retain or log paths, queries or titles.
            let host=raw.flatMap{URL(string:$0)?.host?.lowercased()}
            DispatchQueue.main.async { self.busy=false;completion(host,message) }
        }
    }
}
