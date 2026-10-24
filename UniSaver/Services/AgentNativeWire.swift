import Foundation

/// Wire-format translation only. All providers share the same tool validation and executor.
enum AgentNativeWire {
    static func arguments(_ function: [String: Any]) throws -> [String: Any] {
        guard let raw = function["arguments"] as? String, let data = raw.data(using: .utf8),
              let args = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIRevisionError.emptyResponse }
        return args
    }
    static func encoded(_ value: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value, options: .sortedKeys), as: UTF8.self)
    }
    static func claudeMessages(_ messages: [[String: Any]]) throws -> [[String: Any]] {
        var converted: [[String: Any]] = []
        for message in messages {
            let role = message["role"] as? String ?? "user"
            var blocks: [[String: Any]] = []
            if role == "tool" {
                blocks.append(["type": "tool_result", "tool_use_id": message["tool_call_id"]!, "content": message["content"] ?? ""])
            } else {
                if let text = message["content"] as? String, !text.isEmpty { blocks.append(["type": "text", "text": text]) }
                for call in message["tool_calls"] as? [[String: Any]] ?? [] {
                    guard let function = call["function"] as? [String: Any] else { throw AIRevisionError.emptyResponse }
                    blocks.append(["type": "tool_use", "id": call["id"]!, "name": function["name"]!, "input": try arguments(function)])
                }
            }
            let nativeRole = role == "assistant" ? "assistant" : "user"
            if converted.last?["role"] as? String == nativeRole {
                var last = converted.removeLast()
                last["content"] = (last["content"] as? [[String: Any]] ?? []) + blocks
                converted.append(last)
            } else { converted.append(["role": nativeRole, "content": blocks]) }
        }
        return converted
    }
    static func claudeTurn(_ data: Data) throws -> AgentProviderTurn {
        let body = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = body?["content"] as? [[String: Any]] else { throw AIRevisionError.emptyResponse }
        var text: [String] = [], calls: [AgentToolCall] = []
        for block in content {
            if let value = block["text"] as? String { text.append(value) }
            if block["type"] as? String == "tool_use", let id = block["id"] as? String, let name = block["name"] as? String {
                calls.append(AgentToolCall(id: id, name: name, arguments: try encoded(block["input"] ?? [:])))
            }
        }
        guard !text.isEmpty || !calls.isEmpty else { throw AIRevisionError.emptyResponse }
        return AgentProviderTurn(text: text.joined(separator: "\n"), calls: calls)
    }
    static func geminiSchema(_ value: Any) -> Any {
        if let values = value as? [String: Any] {
            return values.filter { $0.key != "additionalProperties" }.mapValues { geminiSchema($0) }
        }
        if let values = value as? [Any] { return values.map { geminiSchema($0) } }
        return value
    }
    static func geminiMessages(_ messages: [[String: Any]]) throws -> [[String: Any]] {
        var names: [String: String] = [:], converted: [[String: Any]] = []
        for message in messages {
            let role = message["role"] as? String ?? "user"
            var parts: [[String: Any]] = []
            if role == "tool" {
                let id = message["tool_call_id"] as? String ?? ""
                guard let name = names[id] else { throw AIRevisionError.emptyResponse }
                let content = message["content"] as? String ?? "{}"
                let result = (try? JSONSerialization.jsonObject(with: Data(content.utf8))) ?? ["result": content]
                parts.append(["functionResponse": ["name": name, "response": ["result": result]]])
            } else {
                if let text = message["content"] as? String, !text.isEmpty { parts.append(["text": text]) }
                for call in message["tool_calls"] as? [[String: Any]] ?? [] {
                    guard let function = call["function"] as? [String: Any], let name = function["name"] as? String, let id = call["id"] as? String else { throw AIRevisionError.emptyResponse }
                    names[id] = name
                    if let nativePart = call["_nativePart"] as? [String: Any] { parts.append(nativePart) }
                    else { parts.append(["functionCall": ["name": name, "args": try arguments(function)]]) }
                }
            }
            let nativeRole = role == "assistant" ? "model" : "user"
            if converted.last?["role"] as? String == nativeRole {
                var last = converted.removeLast(); last["parts"] = (last["parts"] as? [[String: Any]] ?? []) + parts; converted.append(last)
            } else { converted.append(["role": nativeRole, "parts": parts]) }
        }
        return converted
    }
    static func geminiTurn(_ data: Data) throws -> AgentProviderTurn {
        let body = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let candidates = body?["candidates"] as? [[String: Any]], let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else { throw AIRevisionError.emptyResponse }
        var text: [String] = [], calls: [AgentToolCall] = []
        for part in parts {
            if let value = part["text"] as? String { text.append(value) }
            if let call = part["functionCall"] as? [String: Any], let name = call["name"] as? String {
                calls.append(AgentToolCall(id: UUID().uuidString, name: name, arguments: try encoded(call["args"] ?? [:]), nativePart: part))
            }
        }
        guard !text.isEmpty || !calls.isEmpty else { throw AIRevisionError.emptyResponse }
        return AgentProviderTurn(text: text.joined(separator: "\n"), calls: calls)
    }
}
