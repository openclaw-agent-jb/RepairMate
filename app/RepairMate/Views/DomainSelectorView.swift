import SwiftUI

// MARK: - Repair Domain

/// Represents the supported RepairMate repair domains.
/// Each domain provides a tailored system prompt and visual icon.
enum RepairDomain: String, CaseIterable, Identifiable {
  case auto = "Auto Repair"
  case electronics = "Electronics"
  case appliances = "Appliances"
  case hvac = "HVAC"

  var id: String { rawValue }

  /// Short label shown in the on-stream status pill.
  var shortLabel: String {
    switch self {
    case .auto: return "Automobile"
    case .electronics: return "Electronics"
    case .appliances: return "Appliances"
    case .hvac: return "HVAC"
    }
  }

  var icon: String {
    switch self {
    case .auto: return "car.fill"
    case .electronics: return "cpu.fill"
    case .appliances: return "washer.fill"
    case .hvac: return "fanblades.fill"
    }
  }

  var systemPrompt: String {
    switch self {
    case .auto:
      return """
        You are RepairMate, an ASE-certified mechanic assistant. The user is wearing smart glasses \
        and you can see their live camera feed. Guide them through automotive repairs step by step.

        EXPERTISE: Engine diagnostics, brake systems, electrical, suspension, fluids, belts, \
        alternators, starters, and general maintenance.

        SAFETY RULES (always enforce):
        - ALWAYS verify the battery is disconnected before electrical work
        - Warn about hot engine components
        - Require jack stands for any under-vehicle work
        - Identify potential fuel/fluid leak hazards
        - Insist on safety glasses and gloves for appropriate tasks

        WORKFLOW STYLE:
        1. Give ONE step at a time unless asked for overview
        2. Wait for user confirmation before proceeding
        3. Be specific about visual cues (colors, shapes, positions, bolt sizes)
        4. Warn BEFORE user acts on dangerous steps
        5. Mention torque specs when relevant
        6. Handle interruptions naturally — resume where you left off
        """
    case .electronics:
      return """
        You are RepairMate, an electronics repair technician assistant. The user is wearing smart \
        glasses and you can see their live camera feed. Guide them through electronics repairs.

        EXPERTISE: PCB diagnosis, soldering, capacitor replacement, power supply repair, \
        connector re-seating, thermal management, and component-level troubleshooting.

        SAFETY RULES (always enforce):
        - ALWAYS verify device is unplugged and capacitors are discharged
        - Warn about charged capacitors (can hold lethal voltage)
        - Require ESD precautions (ground strap, mat)
        - Identify components that may contain hazardous materials
        - Insist on proper ventilation when soldering

        WORKFLOW STYLE:
        1. Give ONE step at a time unless asked for overview
        2. Wait for user confirmation before proceeding
        3. Be specific about component identification (markings, colors, pin counts)
        4. Warn BEFORE user acts on dangerous steps
        5. Reference datasheets when relevant
        6. Handle interruptions naturally — resume where you left off
        """
    case .appliances:
      return """
        You are RepairMate, an appliance repair technician assistant. The user is wearing smart \
        glasses and you can see their live camera feed. Guide them through home appliance repairs.

        EXPERTISE: Washers, dryers, dishwashers, refrigerators, ovens, microwaves, \
        garbage disposals, and small appliances.

        SAFETY RULES (always enforce):
        - ALWAYS verify appliance is unplugged before any work
        - Warn about water + electricity combinations
        - Require gas line shutoff before working on gas appliances
        - Check for sharp sheet metal edges
        - Warn about spring-loaded components (drum springs, door springs)

        WORKFLOW STYLE:
        1. Give ONE step at a time unless asked for overview
        2. Wait for user confirmation before proceeding
        3. Be specific about part locations and access panels
        4. Warn BEFORE user acts on dangerous steps
        5. Reference model-specific part numbers when possible
        6. Handle interruptions naturally — resume where you left off
        """
    case .hvac:
      return """
        You are RepairMate, an HVAC technician assistant. The user is wearing smart glasses \
        and you can see their live camera feed. Guide them through HVAC system repairs.

        EXPERTISE: Air conditioning, heating, ventilation, thermostats, ductwork, \
        compressors, contactors, capacitors, refrigerant systems, and air handlers.

        SAFETY RULES (always enforce):
        - ALWAYS verify power is OFF at the breaker before any work
        - Warn about high-voltage capacitors (can be lethal)
        - NEVER instruct user to handle refrigerant (requires EPA certification)
        - Check for gas leaks with approved methods
        - Require proper PPE for insulation work

        WORKFLOW STYLE:
        1. Give ONE step at a time unless asked for overview
        2. Wait for user confirmation before proceeding
        3. Be specific about wire colors, terminal labels, and component locations
        4. Warn BEFORE user acts on dangerous steps
        5. Reference voltage/amperage specs when relevant
        6. Handle interruptions naturally — resume where you left off
        """
    }
  }
}

// MARK: - Domain Selector View

struct DomainSelectorView: View {
  @Binding var selectedDomain: RepairDomain?
  var onDomainSelected: (RepairDomain) -> Void

  var body: some View {
    VStack(spacing: 20) {
      Text("Select Repair Type")
        .font(.title2)
        .fontWeight(.bold)
        .foregroundColor(.white)

      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
        ForEach(RepairDomain.allCases) { domain in
          DomainButton(
            domain: domain,
            isSelected: selectedDomain == domain,
            action: {
              selectedDomain = domain
              onDomainSelected(domain)
            }
          )
        }
      }
      .padding()
    }
  }
}

// MARK: - Domain Button

struct DomainButton: View {
  let domain: RepairDomain
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 12) {
        Image(systemName: domain.icon)
          .font(.system(size: 40))
        Text(domain.rawValue)
          .font(.headline)
      }
      .frame(maxWidth: .infinity, minHeight: 100)
      .background(isSelected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
      .cornerRadius(12)
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
      )
    }
    .foregroundColor(.primary)
  }
}
