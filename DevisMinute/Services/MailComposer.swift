import SwiftUI
import MessageUI

/// Fenêtre d'envoi d'e-mail d'iOS, avec pièce jointe (PDF).
struct MailComposer: UIViewControllerRepresentable {
    struct Attachment {
        let data: Data
        let mimeType: String
        let fileName: String
    }

    let recipient: String
    let subject: String
    let body: String
    let attachment: Attachment?
    let onFinish: (MFMailComposeResult) -> Void

    static var canSendMail: Bool { MFMailComposeViewController.canSendMail() }

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        if !recipient.isEmpty { controller.setToRecipients([recipient]) }
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        if let attachment {
            controller.addAttachmentData(attachment.data, mimeType: attachment.mimeType, fileName: attachment.fileName)
        }
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (MFMailComposeResult) -> Void
        init(onFinish: @escaping (MFMailComposeResult) -> Void) { self.onFinish = onFinish }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            onFinish(result)
        }
    }
}
