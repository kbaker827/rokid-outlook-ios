import SwiftUI

struct GlassesPreviewView: View {
    @EnvironmentObject private var vm: OutlookViewModel
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    glassesMockup
                    commandCard
                    packetCard
                    connectionCard
                }
                .padding()
            }
            .navigationTitle("Glasses Preview")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Glasses mockup

    private var glassesMockup: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black)
                    .aspectRatio(16/4, contentMode: .fit)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15), lineWidth: 1))

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(previewLines, id: \.self) { line in
                        Text(line)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Color(red: 0.2, green: 0.6, blue: 1.0))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
            }
            .padding(.horizontal)
            Text("Rokid AR Glasses · TCP :8099")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var previewLines: [String] {
        guard vm.authManager.isSignedIn else { return ["Sign in to Microsoft Outlook…"] }
        if vm.emails.isEmpty { return ["Loading Outlook data…"] }
        var lines: [String] = ["📧 \(vm.unreadCount) unread"]
        if let e = vm.nextEvent {
            lines.append("\(e.statusIcon) \(e.subject) @ \(e.timeFormatted)")
        }
        if let latest = vm.emails.filter({ !$0.isRead }).first ?? vm.emails.first {
            lines.append("✉️ \(latest.from.displayName): \(latest.subject)")
        }
        return lines
    }

    // MARK: - Command card

    private var commandCard: some View {
        GroupBox("Glasses → Phone Commands") {
            VStack(alignment: .leading, spacing: 8) {
                cmdRow("QUERY: email",          "Show recent inbox emails")
                cmdRow("QUERY: unread",          "Show unread emails only")
                cmdRow("QUERY: flagged",         "Show flagged emails")
                cmdRow("QUERY: important",       "Show high-importance emails")
                cmdRow("QUERY: calendar",        "Show today's events")
                cmdRow("QUERY: next",            "Show the next upcoming event")
                cmdRow("QUERY: contact Sarah",   "Look up Sarah in contacts")
                cmdRow("QUERY: summary",         "Push current summary")
                cmdRow("QUERY: refresh",         "Reload from Microsoft Graph")
                Divider().padding(.vertical, 4)
                Text("Plain text triggers the default summary.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func cmdRow(_ cmd: String, _ desc: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(cmd).font(.system(.caption2, design: .monospaced))
                .padding(5).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 6))
            Text(desc).font(.caption2).foregroundStyle(.secondary).padding(.leading, 6)
        }
    }

    // MARK: - Packet types

    private var packetCard: some View {
        GroupBox("Phone → Glasses Packet Types") {
            VStack(alignment: .leading, spacing: 6) {
                pktRow("outlook",     "📧 5 unread\n✉️ Boss: Q3 Report Due Friday")
                pktRow("email_alert", "❗[IMPORTANT] ✉️ Boss: Q3 Report Due Friday")
                pktRow("event_alert", "📅 Starting in 5 min: Team Standup\n9:00 AM – 9:30 AM")
                pktRow("emails",      "✉️ Boss: Q3 Report…\n● ✉️ Sarah: Quick question about…")
                pktRow("calendar",    "🟢 Standup NOW 9:00–9:30\n📅 Review @ 2:00–3:00 PM")
                pktRow("contact",     "Sarah Jones\n✉️ sarah@company.com\n💼 Product Manager")
                pktRow("status",      "🔍 Searching 'Sarah'…")
                pktRow("error",       "❌ Session expired")
            }
        }
    }

    private func pktRow(_ type: String, _ example: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("{\"type\":\"\(type)\",\"text\":\"...\"}")
                .font(.system(.caption2, design: .monospaced))
            Text(example).font(.caption2).foregroundStyle(.secondary).padding(.leading, 8)
        }
        .padding(6).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Connection

    private var connectionCard: some View {
        GroupBox("Connection") {
            VStack(alignment: .leading, spacing: 6) {
                infoRow("TCP Server",    vm.glassesServer.isRunning ? "Running" : "Stopped",
                        color: vm.glassesServer.isRunning ? .green : .red)
                infoRow("Port",         "8099")
                infoRow("Clients",      "\(vm.glassesServer.clientCount)")
                infoRow("Account",      vm.authManager.currentUser?.email ?? "Not signed in")
                if let r = vm.lastRefresh {
                    infoRow("Last refresh", r.formatted(date: .omitted, time: .shortened))
                }
            }
            .font(.subheadline)
        }
    }

    private func infoRow(_ label: String, _ value: String, color: Color = .secondary) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(color)
        }
    }
}
