import SwiftUI

/// §18.1 — 更新文件服务目录. Uploads an archive that replaces one mount point of a file-service
/// sub-rule's directory.
///
/// Two steps, both server-side: the upload pre-checks the archive and answers a `tempId`, and only
/// the confirmation that follows applies it. This sheet owns the first step; the 确认更新目录 alert
/// that owns the second hangs off the sheet from the page, since an alert raised behind a sheet
/// never appears.
struct WebFolderSheet: View {
    /// Bound to the page, not local: `uploadFolder` reads it through `mountIndexValue` at upload
    /// time, exactly as the original parses `mountIndex` inside `uploadFolderUpdate`.
    @Binding var mountIndex: String
    var busy: Bool
    /// `localError`. The original renders it on the page *behind* the modal, where it cannot be
    /// read; a failed upload or a failed confirmation says so here instead.
    var failure: String
    var close: () -> Void
    var upload: (URL) -> Void

    @State private var picking = false

    var body: some View {
        ServiceSheet(title: "更新文件服务目录", close: { if !busy { close() } }) {
            LuckyPillButton(title: busy ? "处理中" : "选择文件", symbol: "folder.badge.plus",
                            prominent: true, loading: busy) {
                picking = true
            }
        } content: {
            if !failure.isEmpty {
                LuckyErrorCard(message: failure, title: "目录更新失败")
            }
            LuckyCard(spacing: LuckyTheme.Space.m) {
                // `keyboardType: "number-pad"`, and no placeholder — the field opens on `"0"`.
                LuckyTextField(label: "挂载项索引", text: $mountIndex, symbol: "number",
                               mono: true, keyboard: .numberPad)
                Text("选择包含单个根目录的 ZIP、TAR 或 TAR.GZ 文件。上传后会再次确认才应用更新。")
                    .font(LuckyTheme.Text.caption)
                    .foregroundStyle(LuckyTheme.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // The original filters on five archive MIME types; `UTType` has no single archive family
        // that covers .tar.gz, so the picker stays open and the module's own pre-check rejects
        // anything it cannot read.
        .fileImporter(isPresented: $picking, allowedContentTypes: [.item]) { result in
            guard case .success(let url) = result else { return }
            upload(url)
        }
    }
}
