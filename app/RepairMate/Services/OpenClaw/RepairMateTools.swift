import Foundation

// MARK: - RepairMate Tool Declarations

/// Gemini function declarations for RepairMate domain-specific tools.
/// These are appended to ToolDeclarations.allDeclarations() when a repair session is active.
enum RepairMateToolDeclarations {

    static let lookupTorqueSpec: [String: Any] = [
        "name": "lookup_torque_spec",
        "description": "Look up torque specifications for a specific vehicle component or bolt location. Use this when the user needs exact torque values during reassembly.",
        "parameters": [
            "type": "object",
            "properties": [
                "make":          ["type": "string", "description": "Vehicle make (e.g. Honda)"],
                "model":         ["type": "string", "description": "Vehicle model (e.g. Civic)"],
                "year":          ["type": "string", "description": "Model year (e.g. 2015)"],
                "component":     ["type": "string", "description": "Component name (e.g. alternator, brake caliper)"],
                "bolt_location": ["type": "string", "description": "Specific bolt location if known (e.g. upper mounting bolt)"]
            ],
            "required": ["make", "model", "component"]
        ] as [String: Any],
        "behavior": "BLOCKING"
    ]

    static let lookupWiringDiagram: [String: Any] = [
        "name": "lookup_wiring_diagram",
        "description": "Find wiring or circuit diagram information for a vehicle system. Use when the user is confused about electrical connections.",
        "parameters": [
            "type": "object",
            "properties": [
                "system": ["type": "string", "description": "Electrical system (e.g. charging system, ignition, ABS)"],
                "make":   ["type": "string", "description": "Vehicle make"],
                "model":  ["type": "string", "description": "Vehicle model"],
                "year":   ["type": "string", "description": "Model year"]
            ],
            "required": ["system", "make", "model"]
        ] as [String: Any],
        "behavior": "BLOCKING"
    ]

    static let checkPartCompatibility: [String: Any] = [
        "name": "check_part_compatibility",
        "description": "Check if a replacement part is compatible with the user's vehicle. Use when the user has a part number or is unsure if a part fits.",
        "parameters": [
            "type": "object",
            "properties": [
                "part_number": ["type": "string", "description": "OEM or aftermarket part number"],
                "make":        ["type": "string", "description": "Vehicle make"],
                "model":       ["type": "string", "description": "Vehicle model"],
                "year":        ["type": "string", "description": "Model year"]
            ],
            "required": ["make", "model"]
        ] as [String: Any],
        "behavior": "BLOCKING"
    ]

    /// All three RepairMate tool declarations as an array for embedding in setup message.
    static var all: [[String: Any]] {
        [lookupTorqueSpec, lookupWiringDiagram, checkPartCompatibility]
    }

    /// Tool names for routing checks.
    static let names: Set<String> = [
        "lookup_torque_spec",
        "lookup_wiring_diagram",
        "check_part_compatibility"
    ]
}

// MARK: - RepairMate Tool Handler

/// Handles RepairMate tool calls by delegating to the OpenClaw AI agent
/// with a well-formatted task description built from the structured args.
@MainActor
final class RepairMateToolHandler {

    private let bridge: OpenClawBridge

    init(bridge: OpenClawBridge) {
        self.bridge = bridge
    }

    // MARK: - Public

    /// Returns true if this handler owns the given tool name.
    static func canHandle(_ toolName: String) -> Bool {
        RepairMateToolDeclarations.names.contains(toolName)
    }

    /// Execute a RepairMate tool call and return a ToolResult.
    func handle(_ call: GeminiFunctionCall) async -> ToolResult {
        NSLog("[RepairMateTool] Handling: %@ args: %@", call.name, String(describing: call.args))
        let task = buildTask(from: call)
        return await bridge.delegateTask(task: task, toolName: call.name)
    }

    // MARK: - Task Description Builders

    private func buildTask(from call: GeminiFunctionCall) -> String {
        switch call.name {
        case "lookup_torque_spec":
            return buildTorqueTask(args: call.args)
        case "lookup_wiring_diagram":
            return buildWiringTask(args: call.args)
        case "check_part_compatibility":
            return buildCompatibilityTask(args: call.args)
        default:
            return "Look up: \(call.name) \(call.args)"
        }
    }

    private func buildTorqueTask(args: [String: Any]) -> String {
        let year      = args["year"]          as? String ?? ""
        let make      = args["make"]          as? String ?? ""
        let model     = args["model"]         as? String ?? ""
        let component = args["component"]     as? String ?? ""
        let bolt      = args["bolt_location"] as? String ?? ""
        let boltStr   = bolt.isEmpty ? "" : " (\(bolt))"
        return "Search for the exact torque specification in Nm and ft-lbs for the \(component)\(boltStr) on a \(year) \(make) \(model). Provide the specific torque value and any relevant notes about the fastener."
    }

    private func buildWiringTask(args: [String: Any]) -> String {
        let year   = args["year"]   as? String ?? ""
        let make   = args["make"]   as? String ?? ""
        let model  = args["model"]  as? String ?? ""
        let system = args["system"] as? String ?? ""
        return "Find the wiring diagram or electrical connector color codes for the \(system) on a \(year) \(make) \(model). Describe the wire colors, connector pin assignments, and any important notes for diagnosis or repair."
    }

    private func buildCompatibilityTask(args: [String: Any]) -> String {
        let year    = args["year"]        as? String ?? ""
        let make    = args["make"]        as? String ?? ""
        let model   = args["model"]       as? String ?? ""
        let partNum = args["part_number"] as? String ?? ""
        if partNum.isEmpty {
            return "Find compatible replacement parts for the \(year) \(make) \(model). List OEM part numbers and reputable aftermarket alternatives with their compatibility notes."
        }
        return "Check if part number \(partNum) is compatible with a \(year) \(make) \(model). Confirm fitment and list any alternative compatible part numbers."
    }
}

