import Foundation

/// Synchronizes email metadata between IMAP server and local index.
public actor SyncEngine {

    private let imapClient: IMAPClient
    private let metadataIndex: MetadataIndex
    private let accountLabel: String

    public init(imapClient: IMAPClient, metadataIndex: MetadataIndex, accountLabel: String) {
        self.imapClient = imapClient
        self.metadataIndex = metadataIndex
        self.accountLabel = accountLabel
    }

    // MARK: - Initial Sync

    /// Fetch metadata for recent messages across all folders, populate index.
    public func initialSync(account: Account, days: Int = 30) async throws {
        let folders = try await imapClient.listFolders()

        let sinceDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()

        for folder in folders where folder.isSelectable {
            let criteria = IMAPSearchCriteria.since(sinceDate)
            let uids = try await imapClient.searchMessages(folder: folder.name, criteria: criteria)

            guard !uids.isEmpty else { continue }

            let start = uids.min() ?? 1
            let end = uids.max() ?? start
            let range = UIDRange(start: start, end: end)
            let summaries = try await imapClient.fetchMessageSummaries(folder: folder.name, range: range)

            let uidSet = Set(uids)
            for summary in summaries where uidSet.contains(summary.uid) {
                let emailSummary = convertToEmailSummary(summary, folder: folder.name)
                try metadataIndex.upsertMessage(emailSummary)
            }

            // Save sync state
            let uidValidity = try await imapClient.getUIDValidity(folder: folder.name)
            let modSeq = try await imapClient.getHighestModSeq(folder: folder.name)
            let state = SyncState(
                accountLabel: accountLabel,
                folder: folder.name,
                uidValidity: uidValidity,
                highestModSeq: modSeq,
                lastSync: Date()
            )
            try metadataIndex.updateSyncState(state)
        }
    }

    // MARK: - Incremental Sync

    /// Use CONDSTORE if available, otherwise UID-based delta.
    public func incrementalSync(account: Account, folder: String) async throws {
        let localState = try metadataIndex.getSyncState(account: accountLabel, folder: folder)

        // Check UID validity
        let serverUidValidity = try await imapClient.getUIDValidity(folder: folder)
        if let local = localState, local.uidValidity != serverUidValidity {
            // UIDs invalidated – full re-sync needed
            try await fullReconciliation(account: account, folder: folder)
            return
        }

        // Try CONDSTORE incremental
        if let local = localState, let modSeq = local.highestModSeq, modSeq > 0 {
            let changed = try await imapClient.fetchChangedSince(folder: folder, modSeq: modSeq)
            for summary in changed {
                let emailSummary = convertToEmailSummary(summary, folder: folder)
                try metadataIndex.upsertMessage(emailSummary)
            }
        } else {
            // No CONDSTORE – fetch all UIDs and compare
            let serverUids = try await imapClient.searchMessages(folder: folder, criteria: .all)
            let localMessages = try metadataIndex.listMessages(
                account: accountLabel,
                folder: folder,
                limit: Int.max,
                offset: 0,
                sort: .dateDescending
            )
            let localUids = Set(localMessages.compactMap(\.uid))
            let serverUidSet = Set(serverUids)

            // Fetch new messages
            let newUids = serverUidSet.subtracting(localUids)
            if !newUids.isEmpty {
                let start = newUids.min() ?? 1
                let end = newUids.max() ?? start
                let range = UIDRange(start: start, end: end)
                let summaries = try await imapClient.fetchMessageSummaries(folder: folder, range: range)
                for summary in summaries where newUids.contains(summary.uid) {
                    let emailSummary = convertToEmailSummary(summary, folder: folder)
                    try metadataIndex.upsertMessage(emailSummary)
                }
            }

            // Remove deleted messages
            let deletedUids = localUids.subtracting(serverUidSet)
            for uid in deletedUids {
                let id = "\(accountLabel)/\(folder)/\(uid)"
                try metadataIndex.deleteMessage(id: id, account: accountLabel)
            }
        }

        // Update sync state
        let uidValidity = try await imapClient.getUIDValidity(folder: folder)
        let modSeq = try await imapClient.getHighestModSeq(folder: folder)
        let state = SyncState(
            accountLabel: accountLabel,
            folder: folder,
            uidValidity: uidValidity,
            highestModSeq: modSeq,
            lastSync: Date()
        )
        try metadataIndex.updateSyncState(state)
    }

    // MARK: - Full Reconciliation

    /// Compare local UIDs with server, add/remove as needed.
    public func fullReconciliation(account: Account, folder: String) async throws {
        let serverUids = try await imapClient.searchMessages(folder: folder, criteria: .all)

        let localMessages = try metadataIndex.listMessages(
            account: accountLabel,
            folder: folder,
            limit: Int.max,
            offset: 0,
            sort: .dateDescending
        )
        let localUids = Set(localMessages.compactMap(\.uid))
        let serverUidSet = Set(serverUids)

        // Add missing
        let missing = serverUidSet.subtracting(localUids)
        if !missing.isEmpty {
            let start = missing.min() ?? 1
            let end = missing.max() ?? start
            let range = UIDRange(start: start, end: end)
            let summaries = try await imapClient.fetchMessageSummaries(folder: folder, range: range)
            for summary in summaries where missing.contains(summary.uid) {
                let emailSummary = convertToEmailSummary(summary, folder: folder)
                try metadataIndex.upsertMessage(emailSummary)
            }
        }

        // Remove stale
        let stale = localUids.subtracting(serverUidSet)
        for uid in stale {
            let id = "\(accountLabel)/\(folder)/\(uid)"
            try metadataIndex.deleteMessage(id: id, account: accountLabel)
        }

        // Update sync state
        let uidValidity = try await imapClient.getUIDValidity(folder: folder)
        let modSeq = try await imapClient.getHighestModSeq(folder: folder)
        let state = SyncState(
            accountLabel: accountLabel,
            folder: folder,
            uidValidity: uidValidity,
            highestModSeq: modSeq,
            lastSync: Date()
        )
        try metadataIndex.updateSyncState(state)
    }

    // MARK: - New Mail

    /// Called by IDLE monitor when new mail arrives.
    public func handleNewMail(folder: String) async throws {
        let localState = try metadataIndex.getSyncState(account: accountLabel, folder: folder)

        // Fetch only messages newer than what we have
        if let local = localState, let modSeq = local.highestModSeq, modSeq > 0 {
            let changed = try await imapClient.fetchChangedSince(folder: folder, modSeq: modSeq)
            for summary in changed {
                let emailSummary = convertToEmailSummary(summary, folder: folder)
                try metadataIndex.upsertMessage(emailSummary)
            }
        } else {
            // Fetch recent messages
            let uids = try await imapClient.searchMessages(folder: folder, criteria: .unseen)
            if !uids.isEmpty {
                let start = uids.min() ?? 1
                let end = uids.max() ?? start
                let range = UIDRange(start: start, end: end)
                let summaries = try await imapClient.fetchMessageSummaries(folder: folder, range: range)
                let uidSet = Set(uids)
                for summary in summaries where uidSet.contains(summary.uid) {
                    let emailSummary = convertToEmailSummary(summary, folder: folder)
                    try metadataIndex.upsertMessage(emailSummary)
                }
            }
        }

        // Update sync state
        let modSeq = try await imapClient.getHighestModSeq(folder: folder)
        if let modSeq = modSeq {
            let uidValidity = try await imapClient.getUIDValidity(folder: folder)
            let state = SyncState(
                accountLabel: accountLabel,
                folder: folder,
                uidValidity: uidValidity,
                highestModSeq: modSeq,
                lastSync: Date()
            )
            try metadataIndex.updateSyncState(state)
        }
    }

    // MARK: - Helpers

    private func convertToEmailSummary(_ imap: IMAPMessageSummary, folder: String) -> EmailSummary {
        let id = "\(accountLabel)/\(folder)/\(imap.uid)"
        return EmailSummary(
            id: id,
            account: accountLabel,
            folder: folder,
            from: imap.envelope.from.first ?? EmailAddress(email: "unknown@unknown.com"),
            to: imap.envelope.to,
            cc: imap.envelope.cc,
            subject: imap.envelope.subject ?? "(No Subject)",
            date: imap.envelope.date ?? Date(),
            flags: imap.flags,
            size: imap.size,
            hasAttachments: imap.hasAttachments,
            uid: imap.uid,
            messageId: imap.envelope.messageId,
            inReplyTo: imap.envelope.inReplyTo
        )
    }
}
