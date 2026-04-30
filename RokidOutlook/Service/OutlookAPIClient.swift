import Foundation

actor OutlookAPIClient {

    private let base = "https://graph.microsoft.com/v1.0"

    // MARK: - Me

    func fetchMe(token: String) async throws -> (name: String, email: String) {
        let json = try await get("/me", token: token)
        guard let name = json["displayName"] as? String,
              let mail = json["mail"] as? String ?? (json["userPrincipalName"] as? String)
        else { throw GraphError.parseError("me") }
        return (name, mail)
    }

    // MARK: - Mail

    func fetchInbox(
        token: String,
        limit: Int = 20,
        unreadOnly: Bool = false
    ) async throws -> [OutlookEmail] {
        var path = "/me/mailFolders/inbox/messages?$top=\(limit)&$orderby=receivedDateTime desc"
        path += "&$select=id,subject,bodyPreview,from,toRecipients,receivedDateTime,isRead,importance,hasAttachments,flag,conversationId"
        if unreadOnly { path += "&$filter=isRead eq false" }
        let json = try await get(path, token: token)
        guard let items = json["value"] as? [[String: Any]] else { return [] }
        return items.compactMap { parseEmail($0, folder: "inbox") }
    }

    func fetchFolder(
        folderId: String,
        token: String,
        limit: Int = 20
    ) async throws -> [OutlookEmail] {
        let path = "/me/mailFolders/\(folderId)/messages?$top=\(limit)&$orderby=receivedDateTime desc&$select=id,subject,bodyPreview,from,toRecipients,receivedDateTime,isRead,importance,hasAttachments,flag,conversationId"
        let json = try await get(path, token: token)
        guard let items = json["value"] as? [[String: Any]] else { return [] }
        return items.compactMap { parseEmail($0, folder: folderId) }
    }

    func fetchUnreadCount(token: String) async throws -> Int {
        let json = try await get("/me/mailFolders/inbox?$select=unreadItemCount", token: token)
        return json["unreadItemCount"] as? Int ?? 0
    }

    func fetchMailFolders(token: String) async throws -> [MailFolder] {
        let json = try await get("/me/mailFolders?$top=20&$select=id,displayName,unreadItemCount,totalItemCount", token: token)
        guard let items = json["value"] as? [[String: Any]] else { return [] }
        return items.compactMap { dict -> MailFolder? in
            guard let id   = dict["id"]          as? String,
                  let name = dict["displayName"] as? String else { return nil }
            return MailFolder(
                id:           id,
                displayName:  name,
                unreadCount:  dict["unreadItemCount"] as? Int ?? 0,
                totalCount:   dict["totalItemCount"]  as? Int ?? 0
            )
        }
    }

    /// Mark an email as read.
    func markAsRead(emailId: String, token: String) async throws {
        let body: [String: Any] = ["isRead": true]
        _ = try await patch("/me/messages/\(emailId)", body: body, token: token)
    }

    /// Flag an email.
    func flagEmail(emailId: String, token: String) async throws {
        let body: [String: Any] = ["flag": ["flagStatus": "flagged"]]
        _ = try await patch("/me/messages/\(emailId)", body: body, token: token)
    }

    // MARK: - Calendar

    func fetchTodaysEvents(token: String) async throws -> [OutlookEvent] {
        let cal      = Calendar.current
        let startDay = cal.startOfDay(for: Date())
        let endDay   = cal.date(byAdding: .day, value: 1, to: startDay)!
        return try await fetchEvents(from: startDay, to: endDay, token: token)
    }

    func fetchUpcomingEvents(token: String, hours: Int = 24) async throws -> [OutlookEvent] {
        let start = Date()
        let end   = start.addingTimeInterval(TimeInterval(hours * 3600))
        return try await fetchEvents(from: start, to: end, token: token)
    }

    private func fetchEvents(from start: Date, to end: Date, token: String) async throws -> [OutlookEvent] {
        let iso = ISO8601DateFormatter()
        let s   = iso.string(from: start).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let e   = iso.string(from: end).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let path = "/me/calendarView?startDateTime=\(s)&endDateTime=\(e)&$top=20&$orderby=start/dateTime&$select=id,subject,bodyPreview,start,end,location,organizer,isOnlineMeeting,onlineMeetingUrl,isAllDay,showAs,importance,attendees,responseStatus"
        let json = try await get(path, token: token)
        guard let items = json["value"] as? [[String: Any]] else { return [] }
        return items.compactMap { parseEvent($0) }
    }

    // MARK: - Contacts

    func searchContacts(query: String, token: String) async throws -> [OutlookContact] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let path = "/me/contacts?$filter=contains(displayName,'\(encoded)') or contains(emailAddresses/any(a:a/address),'\(encoded)')&$top=10&$select=id,displayName,emailAddresses,phones,jobTitle,companyName"
        let json = try await get(path, token: token)
        guard let items = json["value"] as? [[String: Any]] else { return [] }
        return items.compactMap { parseContact($0) }
    }

    func fetchContacts(token: String, limit: Int = 20) async throws -> [OutlookContact] {
        let path = "/me/contacts?$top=\(limit)&$orderby=displayName&$select=id,displayName,emailAddresses,phones,jobTitle,companyName"
        let json = try await get(path, token: token)
        guard let items = json["value"] as? [[String: Any]] else { return [] }
        return items.compactMap { parseContact($0) }
    }

    // MARK: - HTTP helpers

    private func get(_ path: String, token: String) async throws -> [String: Any] {
        guard let url = URL(string: base + path) else { throw GraphError.parseError("URL") }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20
        return try await execute(req)
    }

    private func patch(_ path: String, body: [String: Any], token: String) async throws -> [String: Any] {
        guard let url = URL(string: base + path) else { throw GraphError.parseError("URL") }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)",  forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 20
        return try await execute(req)
    }

    private func execute(_ req: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 { throw GraphError.unauthorized }
            if http.statusCode == 403 { throw GraphError.forbidden }
            if http.statusCode == 404 { return [:] }
            if !(200..<300).contains(http.statusCode) {
                throw GraphError.httpError(http.statusCode)
            }
        }
        if data.isEmpty { return [:] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GraphError.parseError("JSON")
        }
        if let errObj = json["error"] as? [String: Any],
           let msg    = errObj["message"] as? String {
            throw GraphError.apiError(msg)
        }
        return json
    }

    // MARK: - Parsers

    private func parseEmail(_ dict: [String: Any], folder: String) -> OutlookEmail? {
        guard let id      = dict["id"]      as? String,
              let subject = dict["subject"] as? String
        else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso2 = ISO8601DateFormatter()

        func parseDate(_ key: String) -> Date {
            guard let s = dict[key] as? String else { return Date() }
            return iso.date(from: s) ?? iso2.date(from: s) ?? Date()
        }

        func parseAddress(_ container: [String: Any]?) -> EmailAddress {
            let addr = container?["emailAddress"] as? [String: Any]
            return EmailAddress(
                name:    addr?["name"]    as? String ?? "",
                address: addr?["address"] as? String ?? ""
            )
        }

        let fromDict = dict["from"] as? [String: Any]
        let toArray  = (dict["toRecipients"] as? [[String: Any]]) ?? []
        let flagDict = dict["flag"] as? [String: Any]
        let flagStatus = flagDict?["flagStatus"] as? String ?? "notFlagged"

        return OutlookEmail(
            id:               id,
            subject:          subject.isEmpty ? "(no subject)" : subject,
            bodyPreview:      dict["bodyPreview"]    as? String ?? "",
            from:             parseAddress(fromDict),
            toRecipients:     toArray.map { parseAddress($0) },
            receivedDateTime: parseDate("receivedDateTime"),
            isRead:           dict["isRead"]         as? Bool ?? true,
            isImportant:      (dict["importance"]    as? String ?? "normal") == "high",
            hasAttachments:   dict["hasAttachments"] as? Bool ?? false,
            flag:             EmailFlag(rawValue: flagStatus) ?? .notFlagged,
            conversationId:   dict["conversationId"] as? String ?? "",
            folder:           folder
        )
    }

    private func parseEvent(_ dict: [String: Any]) -> OutlookEvent? {
        guard let id      = dict["id"]      as? String,
              let subject = dict["subject"] as? String
        else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso2 = ISO8601DateFormatter()

        func parseNestedDate(_ key: String) -> Date {
            let container = dict[key] as? [String: Any]
            guard let s   = container?["dateTime"] as? String else { return Date() }
            // Graph returns local time without timezone in calendarView
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSS"
            fmt.timeZone   = TimeZone.current
            return fmt.date(from: s) ?? iso.date(from: s) ?? iso2.date(from: s) ?? Date()
        }

        let organizer = (dict["organizer"] as? [String: Any]).flatMap { orgDict -> EmailAddress? in
            let addr = orgDict["emailAddress"] as? [String: Any]
            return EmailAddress(name: addr?["name"] as? String ?? "", address: addr?["address"] as? String ?? "")
        }

        let attendees = (dict["attendees"] as? [[String: Any]])?.count ?? 0
        let responseDict = dict["responseStatus"] as? [String: Any]
        let responseRaw  = responseDict?["response"] as? String ?? "none"

        let loc = (dict["location"] as? [String: Any])?["displayName"] as? String
        let joinURL = dict["onlineMeetingUrl"] as? String

        return OutlookEvent(
            id:              id,
            subject:         subject.isEmpty ? "(no subject)" : subject,
            bodyPreview:     dict["bodyPreview"]     as? String ?? "",
            start:           parseNestedDate("start"),
            end:             parseNestedDate("end"),
            location:        (loc?.isEmpty ?? true) ? nil : loc,
            organizer:       organizer,
            isOnlineMeeting: dict["isOnlineMeeting"] as? Bool ?? false,
            joinURL:         joinURL,
            isAllDay:        dict["isAllDay"]        as? Bool ?? false,
            showAs:          ShowAsStatus(rawValue: (dict["showAs"] as? String ?? "").lowercased()) ?? .unknown,
            importance:      EventImportance(rawValue: (dict["importance"] as? String ?? "normal").lowercased()) ?? .normal,
            attendeeCount:   attendees,
            responseStatus:  ResponseStatus(rawValue: responseRaw) ?? .none
        )
    }

    private func parseContact(_ dict: [String: Any]) -> OutlookContact? {
        guard let id   = dict["id"]          as? String,
              let name = dict["displayName"] as? String
        else { return nil }

        let emails = (dict["emailAddresses"] as? [[String: Any]])?.compactMap { $0["address"] as? String }
        let phones = (dict["phones"]         as? [[String: Any]])?.compactMap { $0["number"]  as? String }

        return OutlookContact(
            id:          id,
            displayName: name,
            email:       emails?.first,
            phone:       phones?.first,
            jobTitle:    dict["jobTitle"]    as? String,
            company:     dict["companyName"] as? String
        )
    }
}

// MARK: - Errors

enum GraphError: LocalizedError {
    case unauthorized, forbidden, httpError(Int), parseError(String), apiError(String)
    var errorDescription: String? {
        switch self {
        case .unauthorized:        return "Session expired. Please sign in again."
        case .forbidden:           return "Permission denied. Check app permissions in Azure."
        case .httpError(let c):    return "HTTP \(c) from Microsoft Graph."
        case .parseError(let w):   return "Could not parse \(w) from response."
        case .apiError(let msg):   return "Graph error: \(msg)"
        }
    }
}
