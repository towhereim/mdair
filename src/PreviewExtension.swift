import Cocoa
import Quartz
import WebKit

// MARK: - Markdown Renderer

struct MarkdownRenderer {
    func render(_ markdown: String) -> String {
        var lines = markdown.components(separatedBy: "\n")
        var output: [String] = []
        var inCodeBlock = false
        var codeBlockContent: [String] = []
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
                        .replacingOccurrences(of: "&", with: "&amp;")
                        .replacingOccurrences(of: "<", with: "&lt;")
                        .replacingOccurrences(of: ">", with: "&gt;")
                    output.append("<pre><code>\(code)</code></pre>")
                    codeBlockContent = []
                    inCodeBlock = false
                } else {
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
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            output.append("<pre><code>\(code)</code></pre>")
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

// MARK: - CSS

let previewCSS = """
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
@media (prefers-color-scheme: light) {
  body { color: #24292f; background: #fff; }
  h1, h2 { border-bottom-color: #d1d9e0; }
  code { background: #eff1f3; } pre { background: #f6f8fa; }
  blockquote { border-left-color: #d1d9e0; color: #59636e; background: #f6f8fa; }
  th { background: #f6f8fa; } th, td { border-color: #d1d9e0; }
  hr { background: #d1d9e0; } a { color: #0969da; }
}
@media (prefers-color-scheme: dark) {
  body { color: #e6edf3; background: #0d1117; }
  h1, h2 { border-bottom-color: #30363d; }
  code { background: #262c36; } pre { background: #161b22; }
  blockquote { border-left-color: #30363d; color: #8b949e; background: #161b22; }
  th { background: #161b22; } th, td { border-color: #30363d; }
  hr { background: #30363d; } a { color: #58a6ff; }
}
"""

// MARK: - QLPreviewingController

class PreviewViewController: NSViewController, QLPreviewingController {
    var webView: WKWebView!

    override func loadView() {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        self.view = webView
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let data = try Data(contentsOf: url)
        let markdown = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        let renderer = MarkdownRenderer()
        let body = renderer.render(markdown)
        let html = "<!DOCTYPE html><html><head><meta charset='utf-8'><style>\(previewCSS)</style></head><body>\(body)</body></html>"
        await MainActor.run {
            webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
        }
    }
}
