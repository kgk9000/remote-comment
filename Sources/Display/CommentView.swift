import SwiftUI

struct CommentView: View {
    let comment: Comment?
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let comment = comment {
                // Thumbnail of the screenshot
                if let nsImage = NSImage(contentsOf: comment.imageURL) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .cornerRadius(8)
                        .shadow(radius: 4)
                }

                // Claude's comment
                Text(comment.text)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                // Timestamp
                Text(comment.timestamp, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Text("Waiting for screenshots...")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                Spacer()
            }
        }
        .padding(20)
        .frame(minWidth: 400, maxWidth: 600, minHeight: 300)
    }
}
