import Cocoa
import Quartz
import WebKit
import Compression

// MARK: - ZIP Parser (Pure Foundation, Sandbox-Safe)

struct ZipEntry {
    let filename: String
    let uncompressedSize: UInt32
    let data: Data
}

struct ZipReader {
    enum ZipError: Error {
        case invalidArchive
        case unsupportedCompression
        case decompressionFailed
        case pathTraversal
    }

    static func readEntries(from fileURL: URL) throws -> [ZipEntry] {
        let data = try Data(contentsOf: fileURL)
        var entries: [ZipEntry] = []
        var offset = 0

        while offset + 30 <= data.count {
            let sig = data.subdata(in: offset..<offset+4)
            // Local file header signature: 0x04034b50
            guard sig == Data([0x50, 0x4b, 0x03, 0x04]) else { break }

            let compressionMethod = data.readUInt16(at: offset + 8)
            let compressedSize = data.readUInt32(at: offset + 18)
            let uncompressedSize = data.readUInt32(at: offset + 22)
            let filenameLen = data.readUInt16(at: offset + 26)
            let extraLen = data.readUInt16(at: offset + 28)

            let filenameStart = offset + 30
            let filenameEnd = filenameStart + Int(filenameLen)
            guard filenameEnd <= data.count else { break }

            let filenameData = data.subdata(in: filenameStart..<filenameEnd)
            let filename = String(data: filenameData, encoding: .utf8) ?? ""

            let dataStart = filenameEnd + Int(extraLen)
            let dataEnd = dataStart + Int(compressedSize)
            guard dataEnd <= data.count else { break }

            // Path traversal protection
            let normalizedPath = filename.replacingOccurrences(of: "\\", with: "/")
            if normalizedPath.contains("..") {
                offset = dataEnd
                continue
            }

            // Skip directories
            if filename.hasSuffix("/") {
                offset = dataEnd
                continue
            }

            let compressedData = data.subdata(in: dataStart..<dataEnd)

            let fileData: Data
            if compressionMethod == 0 {
                // Stored (no compression)
                fileData = compressedData
            } else if compressionMethod == 8 {
                // Deflate
                guard let decompressed = Self.inflate(compressedData, uncompressedSize: Int(uncompressedSize)) else {
                    offset = dataEnd
                    continue
                }
                fileData = decompressed
            } else {
                offset = dataEnd
                continue
            }

            entries.append(ZipEntry(filename: filename, uncompressedSize: uncompressedSize, data: fileData))
            offset = dataEnd
        }

        return entries
    }

    private static func inflate(_ data: Data, uncompressedSize: Int) -> Data? {
        guard uncompressedSize > 0 else { return Data() }
        let destSize = max(uncompressedSize, 256)
        var destBuffer = [UInt8](repeating: 0, count: destSize)

        let result = data.withUnsafeBytes { srcPtr -> Int in
            guard let srcBase = srcPtr.baseAddress else { return 0 }
            return compression_decode_buffer(
                &destBuffer, destSize,
                srcBase.assumingMemoryBound(to: UInt8.self), data.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard result > 0 else { return nil }
        return Data(destBuffer.prefix(result))
    }
}

private extension Data {
    func readUInt16(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return subdata(in: offset..<offset+2).withUnsafeBytes { $0.load(as: UInt16.self) }
    }

    func readUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self) }
    }
}

// MARK: - MdairParser

struct MdairParser {
    struct MdairDocument {
        let markdown: String
        let assets: [String: Data]  // filename -> image data
    }

    func parse(fileURL: URL) throws -> MdairDocument {
        let entries = try ZipReader.readEntries(from: fileURL)

        // Find content.md
        var markdownData: Data?
        if let contentEntry = entries.first(where: { $0.filename == "content.md" }) {
            markdownData = contentEntry.data
        } else if let firstMd = entries.first(where: { $0.filename.hasSuffix(".md") && !$0.filename.contains("/") }) {
            markdownData = firstMd.data
        }

        let markdown: String
        if let md = markdownData {
            markdown = String(data: md, encoding: .utf8) ?? String(data: md, encoding: .isoLatin1) ?? ""
        } else {
            markdown = ""
        }

        // Collect assets
        var assets: [String: Data] = [:]
        for entry in entries {
            if entry.filename.hasPrefix("assets/") && entry.filename.count > 7 {
                let assetName = String(entry.filename.dropFirst(7)) // drop "assets/"
                assets[assetName] = entry.data
            }
        }

        return MdairDocument(markdown: markdown, assets: assets)
    }
}

// MARK: - Markdown Renderer

struct MarkdownRenderer {
    func render(_ markdown: String) -> String {
        var lines = markdown.components(separatedBy: "\n")
        var output: [String] = []
        var inCodeBlock = false
        var codeBlockContent: [String] = []
        var codeBlockLang = ""
        var inList = false
        var inOrderedList = false
        var inBlockquote = false
        var inTable = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code blocks
            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    let code = codeBlockContent.joined(separator: "\n")
                    if codeBlockLang == "mermaid" {
                        output.append("<pre class=\"mermaid\">\(code)</pre>")
                    } else {
                        let escaped = code
                            .replacingOccurrences(of: "&", with: "&amp;")
                            .replacingOccurrences(of: "<", with: "&lt;")
                            .replacingOccurrences(of: ">", with: "&gt;")
                        output.append("<pre><code>\(escaped)</code></pre>")
                    }
                    codeBlockContent = []
                    codeBlockLang = ""
                    inCodeBlock = false
                } else {
                    codeBlockLang = String(trimmed.dropFirst(3))
                    inCodeBlock = true
                }
                continue
            }
            if inCodeBlock {
                codeBlockContent.append(line)
                continue
            }

            // Horizontal rule
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                if inList { output.append("</ul>"); inList = false }
                if inOrderedList { output.append("</ol>"); inOrderedList = false }
                if inBlockquote { output.append("</blockquote>"); inBlockquote = false }
                output.append("<hr>")
                continue
            }

            // Headings
            if let level = headingLevel(trimmed) {
                let content = String(trimmed.dropFirst(level + 1))
                output.append("<h\(level)>\(content)</h\(level)>")
                continue
            }

            // Blockquote
            if trimmed.hasPrefix("> ") {
                if !inBlockquote { output.append("<blockquote>"); inBlockquote = true }
                output.append(String(trimmed.dropFirst(2)))
                continue
            } else if inBlockquote && trimmed.isEmpty {
                output.append("</blockquote>"); inBlockquote = false
            }

            // Table
            if trimmed.hasPrefix("|") && trimmed.contains("|") {
                let cleaned = trimmed.replacingOccurrences(of: "-", with: "")
                    .replacingOccurrences(of: "|", with: "")
                    .replacingOccurrences(of: ":", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if cleaned.isEmpty { continue } // separator row

                let cells = trimmed.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if !inTable {
                    output.append("<table>")
                    inTable = true
                    output.append("<tr>" + cells.map { "<th>\($0)</th>" }.joined() + "</tr>")
                } else {
                    output.append("<tr>" + cells.map { "<td>\($0)</td>" }.joined() + "</tr>")
                }
                continue
            } else if inTable {
                output.append("</table>"); inTable = false
            }

            // Unordered list
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                if inOrderedList { output.append("</ol>"); inOrderedList = false }
                if !inList { output.append("<ul>"); inList = true }
                var content = String(trimmed.dropFirst(2))
                // Checkboxes
                if content.hasPrefix("[ ] ") {
                    content = "<input type='checkbox' disabled> " + String(content.dropFirst(4))
                } else if content.hasPrefix("[x] ") || content.hasPrefix("[X] ") {
                    content = "<input type='checkbox' checked disabled> " + String(content.dropFirst(4))
                }
                output.append("<li>\(content)</li>")
                continue
            } else if inList && trimmed.isEmpty {
                output.append("</ul>"); inList = false
            }

            // Ordered list
            if let range = trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                if inList { output.append("</ul>"); inList = false }
                if !inOrderedList { output.append("<ol>"); inOrderedList = true }
                let content = String(trimmed[range.upperBound...])
                output.append("<li>\(content)</li>")
                continue
            } else if inOrderedList && trimmed.isEmpty {
                output.append("</ol>"); inOrderedList = false
            }

            // Empty line
            if trimmed.isEmpty {
                output.append("")
                continue
            }

            // HTML passthrough — lines starting with < are kept as-is
            if trimmed.hasPrefix("<") {
                output.append(line)
                continue
            }

            // Paragraph
            output.append("<p>\(trimmed)</p>")
        }

        // Close open tags
        if inList { output.append("</ul>") }
        if inOrderedList { output.append("</ol>") }
        if inBlockquote { output.append("</blockquote>") }
        if inTable { output.append("</table>") }
        if inCodeBlock {
            let code = codeBlockContent.joined(separator: "\n")
            if codeBlockLang == "mermaid" {
                output.append("<pre class=\"mermaid\">\(code)</pre>")
            } else {
                let escaped = code
                    .replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;")
                    .replacingOccurrences(of: ">", with: "&gt;")
                output.append("<pre><code>\(escaped)</code></pre>")
            }
        }

        var html = output.joined(separator: "\n")

        // Inline formatting
        html = applyRegex(html, pattern: #"\*\*\*(.*?)\*\*\*"#, template: "<strong><em>$1</em></strong>")
        html = applyRegex(html, pattern: #"\*\*(.*?)\*\*"#, template: "<strong>$1</strong>")
        html = applyRegex(html, pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#, template: "<em>$1</em>")
        html = applyRegex(html, pattern: #"`([^`]+)`"#, template: "<code>$1</code>")
        html = applyRegex(html, pattern: #"~~(.*?)~~"#, template: "<del>$1</del>")
        html = applyRegex(html, pattern: #"!\[([^\]]*)\]\(([^)]+)\)"#, template: "<img src=\"$2\" alt=\"$1\" style=\"max-width:100%;\">")
        html = applyRegex(html, pattern: #"\[([^\]]+)\]\(([^)]+)\)"#, template: "<a href=\"$2\">$1</a>")

        return html
    }

    private func headingLevel(_ line: String) -> Int? {
        for level in (1...6).reversed() {
            let prefix = String(repeating: "#", count: level) + " "
            if line.hasPrefix(prefix) { return level }
        }
        return nil
    }

    private func applyRegex(_ string: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return string }
        let range = NSRange(string.startIndex..., in: string)
        return regex.stringByReplacingMatches(in: string, options: [], range: range, withTemplate: template)
    }
}

// MARK: - QLPreviewingController

class PreviewViewController: NSViewController, QLPreviewingController, WKNavigationDelegate {
    var webView: WKWebView!
    private var loadContinuation: CheckedContinuation<Void, Never>?

    static let css = """
    * { margin: 0; padding: 0; box-sizing: border-box; }
    :root { color-scheme: light dark; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif;
      max-width: 820px; margin: 0 auto; padding: 24px 40px; line-height: 1.7; font-size: 15px;
    }
    h1 { font-size: 2em; margin: 0.8em 0 0.4em; padding-bottom: 0.3em; border-bottom: 1px solid; }
    h2 { font-size: 1.5em; margin: 0.8em 0 0.4em; padding-bottom: 0.2em; border-bottom: 1px solid; }
    h3 { font-size: 1.25em; margin: 0.8em 0 0.4em; }
    h4 { font-size: 1.1em; margin: 0.6em 0 0.3em; }
    h5, h6 { font-size: 1em; margin: 0.6em 0 0.3em; }
    p { margin: 0.6em 0; }
    pre { padding: 16px; border-radius: 8px; overflow-x: auto; font-size: 13px; margin: 1em 0; }
    code { font-family: 'SF Mono', Menlo, monospace; font-size: 0.9em; padding: 2px 6px; border-radius: 4px; }
    pre code { padding: 0; font-size: inherit; }
    blockquote { padding: 8px 16px; margin: 1em 0; border-left: 4px solid; border-radius: 2px; }
    ul, ol { padding-left: 2em; margin: 0.5em 0; }
    li { margin: 0.25em 0; }
    table { border-collapse: collapse; margin: 1em 0; width: 100%; }
    th, td { padding: 8px 12px; border: 1px solid; text-align: left; }
    th { font-weight: 600; }
    hr { border: none; height: 1px; margin: 2em 0; }
    img { max-width: 100%; border-radius: 4px; margin: 0.5em 0; }
    a { text-decoration: none; }
    a:hover { text-decoration: underline; }
    input[type=checkbox] { margin-right: 6px; }
    .mdair-notice {
      padding: 12px 16px; margin-bottom: 20px; border-radius: 8px;
      border-left: 4px solid #f0a020; font-size: 13px; line-height: 1.5;
    }
    .mdair-notice code { padding: 1px 6px; border-radius: 3px; font-size: 12px; }
    #mdair-toast {
      position: fixed; top: 16px; right: 16px;
      padding: 6px 14px; border-radius: 6px;
      font-size: 13px; font-weight: 500;
      background: rgba(40,40,40,0.92); color: #fff;
      opacity: 0; pointer-events: none;
      transform: translateY(-8px);
      transition: opacity 0.18s ease, transform 0.18s ease;
      z-index: 99999;
    }
    #mdair-toast.show { opacity: 1; transform: translateY(0); }
    @media (prefers-color-scheme: light) {
      body { color: #24292f; background: #fff; }
      h1, h2 { border-bottom-color: #d1d9e0; }
      code { background: #eff1f3; } pre { background: #f6f8fa; }
      blockquote { border-left-color: #d1d9e0; color: #59636e; background: #f6f8fa; }
      th { background: #f6f8fa; } th, td { border-color: #d1d9e0; }
      hr { background: #d1d9e0; } a { color: #0969da; }
      .mdair-notice { background: #fff8e1; color: #6b4f00; }
      .mdair-notice code { background: rgba(0,0,0,0.06); }
    }
    @media (prefers-color-scheme: dark) {
      body { color: #e6edf3; background: #0d1117; }
      h1, h2 { border-bottom-color: #30363d; }
      code { background: #262c36; } pre { background: #161b22; }
      blockquote { border-left-color: #30363d; color: #8b949e; background: #161b22; }
      th { background: #161b22; } th, td { border-color: #30363d; }
      hr { background: #30363d; } a { color: #58a6ff; }
      .mdair-notice { background: #2a2410; color: #e0c97a; }
      .mdair-notice code { background: rgba(255,255,255,0.08); }
    }
    """

    override func loadView() {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        webView.allowsMagnification = true
        webView.navigationDelegate = self
        self.view = webView
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func preparePreviewOfFile(at url: URL) async throws {
        if url.pathExtension.lowercased() == "mdair" {
            try await prepareMdairPreview(at: url)
        } else {
            try await prepareMarkdownPreview(at: url)
        }
    }

    private func prepareMarkdownPreview(at url: URL) async throws {
        let data = try Data(contentsOf: url)
        let markdown = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        let renderer = MarkdownRenderer()
        let rendered = renderer.render(markdown)
        let baseDir = url.deletingLastPathComponent()
        let (body, missing) = inlineLocalImages(rendered, baseDir: baseDir)
        let notice = missing > 0 ? """
        <div class="mdair-notice"><strong>로컬 이미지를 표시할 수 없습니다.</strong><br>macOS QuickLook 미리보기는 보안 정책상 미리보기 파일 외 다른 파일에 접근할 수 없습니다. 이미지를 보려면 파일을 더블클릭하여 <strong>mdair</strong> 앱으로 열거나, <code>mdair-convert</code>로 <code>.mdair</code> 형식으로 변환하세요.</div>
        """ : ""
        let html = """
        <!DOCTYPE html><html><head><meta charset='utf-8'>\
        <style>\(PreviewViewController.css)</style></head>\
        <body>\(notice)\(body)\
        <script src='https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js'></script>\
        <script>mermaid.initialize({startOnLoad:true,theme:'default'});</script>\
        <script>(function(){var t=null,m=null;function s(){if(!t){t=document.createElement('div');t.id='mdair-toast';t.textContent='복사됨';document.body.appendChild(t);}t.classList.add('show');clearTimeout(m);m=setTimeout(function(){t.classList.remove('show');},1200);}document.addEventListener('copy',s);})();</script>\
        </body></html>
        """
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                self.loadContinuation = continuation
                self.webView.loadHTMLString(html, baseURL: baseDir)
            }
        }
    }

    private func prepareMdairPreview(at url: URL) async throws {
        let parser = MdairParser()
        let doc = try parser.parse(fileURL: url)

        let renderer = MarkdownRenderer()
        var body = renderer.render(doc.markdown)
        body = inlineAssetsFromMemory(body, assets: doc.assets)

        let html = """
        <!DOCTYPE html><html><head><meta charset='utf-8'>\
        <style>\(PreviewViewController.css)</style></head>\
        <body>\(body)\
        <script src='https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js'></script>\
        <script>mermaid.initialize({startOnLoad:true,theme:'default'});</script>\
        <script>(function(){var t=null,m=null;function s(){if(!t){t=document.createElement('div');t.id='mdair-toast';t.textContent='복사됨';document.body.appendChild(t);}t.classList.add('show');clearTimeout(m);m=setTimeout(function(){t.classList.remove('show');},1200);}document.addEventListener('copy',s);})();</script>\
        </body></html>
        """
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                self.loadContinuation = continuation
                self.webView.loadHTMLString(html, baseURL: nil)
            }
        }
    }

    private func inlineAssetsFromMemory(_ html: String, assets: [String: Data]) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(src|srcset)=\"assets/([^\"]+)\""#, options: []
        ) else { return html }
        var result = html
        let matches = regex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html))
        for match in matches.reversed() {
            guard let attrRange = Range(match.range(at: 1), in: result),
                  let filenameRange = Range(match.range(at: 2), in: result) else { continue }
            let attr = String(result[attrRange])
            let filename = String(result[filenameRange])

            guard let imgData = assets[filename] else {
                // Replace with placeholder for missing images
                let fullRange = match.range(at: 0)
                guard let swiftRange = Range(fullRange, in: result) else { continue }
                result.replaceSubrange(swiftRange, with: "\(attr)=\"data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyMDAiIGhlaWdodD0iNTAiPjx0ZXh0IHg9IjEwIiB5PSIzMCIgZmlsbD0iIzk5OSI+SW1hZ2Ugbm90IGZvdW5kPC90ZXh0Pjwvc3ZnPg==\"")
                continue
            }

            let ext = (filename as NSString).pathExtension.lowercased()
            let mime: String
            switch ext {
            case "png": mime = "image/png"
            case "jpg", "jpeg": mime = "image/jpeg"
            case "gif": mime = "image/gif"
            case "svg": mime = "image/svg+xml"
            case "webp": mime = "image/webp"
            case "tiff", "tif": mime = "image/tiff"
            default: mime = "image/png"
            }

            let b64 = imgData.base64EncodedString()
            let dataURI = "data:\(mime);base64,\(b64)"
            let fullRange = match.range(at: 0)
            guard let swiftRange = Range(fullRange, in: result) else { continue }
            result.replaceSubrange(swiftRange, with: "\(attr)=\"\(dataURI)\"")
        }
        return result
    }

    private func inlineLocalImages(_ html: String, baseDir: URL) -> (html: String, missingCount: Int) {
        guard let regex = try? NSRegularExpression(
            pattern: #"(src|srcset)=\"([^\"]+)\""#, options: []
        ) else { return (html, 0) }
        var result = html
        var missingCount = 0
        let matches = regex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html))
        for match in matches.reversed() {
            guard let attrRange = Range(match.range(at: 1), in: html),
                  let pathRange = Range(match.range(at: 2), in: html) else { continue }
            let attr = String(html[attrRange])
            let path = String(html[pathRange])
            if path.hasPrefix("http://") || path.hasPrefix("https://") || path.hasPrefix("data:") { continue }
            let fileURL = baseDir.appendingPathComponent(path)
            guard let imgData = try? Data(contentsOf: fileURL) else {
                missingCount += 1
                continue
            }
            let ext = fileURL.pathExtension.lowercased()
            let mime = ext == "png" ? "image/png" : ext == "jpg" || ext == "jpeg" ? "image/jpeg" : ext == "gif" ? "image/gif" : ext == "svg" ? "image/svg+xml" : "image/png"
            let b64 = imgData.base64EncodedString()
            let dataURI = "data:\(mime);base64,\(b64)"
            let fullRange = match.range(at: 0)
            guard let swiftRange = Range(fullRange, in: result) else { continue }
            result.replaceSubrange(swiftRange, with: "\(attr)=\"\(dataURI)\"")
        }
        return (result, missingCount)
    }
}
