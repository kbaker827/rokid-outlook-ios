import SwiftUI

struct InboxView: View {
    @EnvironmentObject private var vm: OutlookViewModel
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        NavigationStack {
            Group {
                if !vm.authManager.isSignedIn {
                    signInView
                } else {
                    mainContent
                }
            }
            .navigationTitle("Outlook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { serverDot }
                ToolbarItem(placement: .navigationBarTrailing) { refreshButton }
            }
        }
    }

    // MARK: - Sign in

    private var signInView: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "envelope.fill")
                .font(.system(size: 64))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)

            VStack(spacing: 8) {
                Text("Rokid Outlook HUD")
                    .font(.title.weight(.bold))
                Text("See your emails and calendar on your Rokid AR glasses.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if settings.clientId.isEmpty {
                Label("Add your Azure App Client ID in Settings first", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding(.horizontal)
            }

            Button {
                Task { await vm.authManager.signIn() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "envelope.badge.shield.half.filled.fill")
                    Text("Sign in with Microsoft")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: 280)
                .padding(.vertical, 14)
                .background(Color(red: 0.0, green: 0.47, blue: 0.83), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
            }
            .disabled(settings.clientId.isEmpty)

            if vm.authManager.isSigningIn { ProgressView("Signing in…") }
            Spacer()
        }
    }

    // MARK: - Main content

    private var mainContent: some View {
        VStack(spacing: 0) {
            summaryBar
            Divider()

            if vm.isLoading && vm.emails.isEmpty {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emailList
            }
        }
    }

    // MARK: - Summary bar

    private var summaryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Unread count
                summaryChip(
                    icon: "envelope.badge.fill",
                    label: "\(vm.unreadCount) unread",
                    color: vm.unreadCount > 0 ? .blue : .secondary
                )

                // Next event
                if let event = vm.nextEvent {
                    let mins = event.minutesUntilStart
                    summaryChip(
                        icon: event.isNow ? "calendar.badge.clock" : "calendar",
                        label: mins == 0 ? "NOW: \(event.subject)" : "In \(mins)m: \(event.subject)",
                        color: event.isNow ? .green : event.isUpcoming ? .orange : .secondary
                    )
                }

                // Flagged
                let flagged = vm.emails.filter { $0.flag == .flagged }.count
                if flagged > 0 {
                    summaryChip(icon: "flag.fill", label: "\(flagged) flagged", color: .orange)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(Color(.secondarySystemBackground))
    }

    private func summaryChip(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption).foregroundStyle(color)
            Text(label).font(.caption.weight(.medium)).foregroundStyle(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(.systemBackground), in: Capsule())
    }

    // MARK: - Email list

    private var emailList: some View {
        List {
            // Today's events section
            if !vm.todaysEvents.isEmpty {
                Section("Today's Calendar") {
                    ForEach(vm.todaysEvents.prefix(3)) { event in
                        EventRow(event: event)
                    }
                }
            }

            // Emails
            Section("Inbox\(vm.unreadCount > 0 ? " (\(vm.unreadCount) unread)" : "")") {
                if vm.filteredEmails.isEmpty {
                    Text("No emails").foregroundStyle(.secondary).font(.subheadline)
                } else {
                    ForEach(vm.filteredEmails) { email in
                        EmailRow(email: email)
                            .swipeActions(edge: .leading) {
                                Button {
                                    if !email.isRead { vm.markAsRead(email) }
                                } label: {
                                    Label("Read", systemImage: "envelope.open")
                                }
                                .tint(.blue)
                            }
                    }
                }
            }

            if let refresh = vm.lastRefresh {
                Section {
                    Text("Updated \(refresh.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .listRowBackground(Color.clear)
            }
        }
        .searchable(text: $vm.searchQuery, prompt: "Search emails…")
        .refreshable { await vm.refresh() }
    }

    // MARK: - Toolbar

    private var serverDot: some View {
        HStack(spacing: 4) {
            Circle().fill(vm.glassesServer.isRunning ? .green : .red).frame(width: 8, height: 8)
            Text(":8099").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var refreshButton: some View {
        Button { Task { await vm.refresh() } } label: {
            vm.isLoading ? AnyView(ProgressView().scaleEffect(0.8)) : AnyView(Image(systemName: "arrow.clockwise"))
        }
        .disabled(vm.isLoading || !vm.authManager.isSignedIn)
    }
}

// MARK: - Email row

struct EmailRow: View {
    let email: OutlookEmail
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 8) {
                // Unread dot
                Circle()
                    .fill(email.isRead ? Color.clear : Color.blue)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(email.from.displayName)
                            .font(.subheadline.weight(email.isRead ? .regular : .semibold))
                            .lineLimit(1)
                        Spacer()
                        HStack(spacing: 4) {
                            if email.hasAttachments { Image(systemName: "paperclip").font(.caption2).foregroundStyle(.secondary) }
                            if email.isImportant    { Image(systemName: "exclamationmark").font(.caption2).foregroundStyle(.red) }
                            if email.flag == .flagged { Image(systemName: "flag.fill").font(.caption2).foregroundStyle(.orange) }
                            Text(email.ageFormatted).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    Text(email.subject)
                        .font(.footnote.weight(email.isRead ? .regular : .medium))
                        .lineLimit(1)
                    if !email.bodyPreview.isEmpty {
                        Text(email.bodyPreview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(expanded ? 4 : 1)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }
        .listRowBackground(email.isRead ? Color.clear : Color.blue.opacity(0.04))
    }
}

// MARK: - Event row

struct EventRow: View {
    let event: OutlookEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(event.statusIcon).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.subject).font(.subheadline.weight(.medium)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(event.timeFormatted).font(.caption).foregroundStyle(.secondary)
                    if event.isOnlineMeeting {
                        Image(systemName: "video.fill").font(.caption2).foregroundStyle(.blue)
                    }
                    if let loc = event.location {
                        Text("· \(loc)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Text(event.responseStatus.displayName).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            if event.isNow {
                Text("NOW").font(.caption2.weight(.bold))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.green.opacity(0.2), in: Capsule()).foregroundStyle(.green)
            } else if event.isUpcoming {
                Text("\(event.minutesUntilStart)m")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.orange.opacity(0.2), in: Capsule()).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }
}
