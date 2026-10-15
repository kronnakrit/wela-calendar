import SwiftUI
import WelaCore

struct MonthHeader: View {
  @ObservedObject var vm: PanelViewModel

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Button(action: vm.goToToday) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(vm.monthName).welaFont(26, weight: .semibold, serif: true).foregroundStyle(Theme.ink)
          Text(vm.yearString).welaFont(26, weight: .semibold, serif: true)
            .foregroundStyle(Theme.redPen)
        }
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(vm.monthName) \(vm.yearString)")
      .accessibilityHint("Jump to today")
      Spacer()
      Button { vm.moveMonth(by: -1) } label: {
        Image(systemName: "chevron.left").frame(width: 24, height: 24)
      }
      .accessibilityLabel("Previous month")
      Button { vm.moveMonth(by: 1) } label: {
        Image(systemName: "chevron.right").frame(width: 24, height: 24)
      }
      .accessibilityLabel("Next month")
    }
    .buttonStyle(.plain)
    .foregroundStyle(Theme.softInk)
  }
}

struct MonthGrid: View {
  @ObservedObject var vm: PanelViewModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let cells = vm.gridCells
    let rows = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        ForEach(Array(vm.weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
          Text(symbol.uppercased(with: vm.locale))
            .welaFont(10.5, weight: .semibold)
            .foregroundStyle(index == vm.todayWeekdayIndex ? Theme.redPen : Theme.softInk)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
        }
      }
      .padding(.bottom, 4)
      ForEach(rows.indices, id: \.self) { r in
        let row = rows[r]
        HStack(spacing: 0) {
          ForEach(row) { cell in
            DayCellView(
              cell: cell, vm: vm, isSelected: vm.calendar.isDate(cell.date, inSameDayAs: vm.selectedDay)
            )
          }
        }
        .background(
          RoundedRectangle(cornerRadius: 8).fill(
            row.contains { vm.calendar.isDate($0.date, inSameDayAs: vm.now) }
              ? Theme.highlighter : Color.clear)
        )
      }
    }
    .animation(WelaAnimation.standard(reduceMotion: reduceMotion), value: vm.selectedDay)
  }
}

struct DayCellView: View {
  let cell: DayCell
  @ObservedObject var vm: PanelViewModel
  let isSelected: Bool

  var body: some View {
    let dots = vm.dots(for: cell.date)
    let count = vm.agendaFor(cell.date).count
    Button {
      vm.select(day: cell.date)
    } label: {
      VStack(spacing: 2) {
        ZStack {
          if cell.isToday {
            Ellipse().stroke(Theme.redPen, lineWidth: 1.5).frame(width: 30, height: 25)
              .rotationEffect(.degrees(-10))
          } else if isSelected {
            Circle().stroke(Theme.rule, lineWidth: 1).frame(width: 27, height: 27)
          }
          Text("\(vm.calendar.component(.day, from: cell.date))")
            .welaFont(14, weight: cell.isToday ? .semibold : .regular)
            .monospacedDigit()
            .foregroundStyle(
              cell.isInMonth ? (cell.isToday ? Theme.redPen : Theme.ink) : Theme.pencil)
        }
        .frame(height: 28)
        HStack(spacing: 2) {
          ForEach(dots.indices, id: \.self) { i in
            Circle().fill(dots[i]).frame(width: 4, height: 4)
          }
        }
        .frame(height: 5)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 2)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .simultaneousGesture(
      TapGesture(count: 2).onEnded {
        vm.select(day: cell.date)
        if let first = vm.agendaItems.first { vm.selectedEventID = first.id; vm.openSelectedEvent() }
      })
    .accessibilityLabel(label(count: count))
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private func label(count: Int) -> String {
    var parts = [vm.formatted(cell.date, "EEEE d MMMM")]
    parts.append(count == 1 ? "1 event" : "\(count) events")
    if cell.isToday { parts.append("today") }
    return parts.joined(separator: ", ")
  }
}
