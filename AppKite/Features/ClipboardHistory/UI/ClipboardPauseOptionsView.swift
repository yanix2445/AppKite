import SwiftUI

struct ClipboardPauseOptionsView: View {
    var compactLabels = false
    let onPause: (ClipboardCollectionPause) -> Void

    var body: some View {
        Button("Jusqu’à la reprise manuelle") { onPause(.manual) }
        ForEach([5, 15, 60], id: \.self) { minutes in
            Button {
                onPause(.until(.now.addingTimeInterval(Double(minutes * 60))))
            } label: {
                if compactLabels {
                    Text("\(minutes) min")
                } else if minutes == 60 {
                    Text("1 heure")
                } else {
                    Text("\(minutes) minutes")
                }
            }
        }
    }
}
