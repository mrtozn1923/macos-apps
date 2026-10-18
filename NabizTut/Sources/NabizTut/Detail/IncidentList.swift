import SwiftUI

struct IncidentList: View {
    let incidents: [Incident]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Outages")).font(.headline)
            if incidents.isEmpty {
                Label(L("No outages in this period"), systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(incidents) { incident in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Circle().fill(incident.ended == nil ? Color.red : Color.secondary.opacity(0.5))
                                .frame(width: 7, height: 7)
                            Text(incident.started.formatted(date: .abbreviated, time: .shortened))
                                .monospacedDigit()
                                .frame(width: 150, alignment: .leading)
                            Text(incident.ended == nil ? L("Ongoing · %@", DurationFormatter.short(incident.duration))
                                                       : DurationFormatter.short(incident.duration))
                                .foregroundStyle(incident.ended == nil ? .red : .primary)
                                .frame(width: 110, alignment: .leading)
                            Text(incident.reason).foregroundStyle(.secondary).lineLimit(2)
                            Spacer(minLength: 0)
                        }
                        .font(.callout)
                        .padding(.vertical, 8)
                        Divider()
                    }
                }
            }
        }
    }
}
