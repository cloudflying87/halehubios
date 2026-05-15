import SwiftUI
import UIKit

struct CookModeView: View {
    @Environment(\.dismiss) var dismiss
    let title: String
    let steps: [String]

    @State private var currentStep = 0
    @State private var showAllSteps = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Done") { dismiss() }
                        .font(.body)
                    Spacer()
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        showAllSteps = true
                    } label: {
                        Image(systemName: "list.number")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                Divider()

                // Step counter
                HStack(spacing: 4) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        Capsule()
                            .fill(i == currentStep ? Color.accentColor : Color(.systemGray4))
                            .frame(height: 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .animation(.spring, value: currentStep)

                Text("Step \(currentStep + 1) of \(steps.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)

                // Step content
                Spacer()

                Text(steps[currentStep])
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .id(currentStep)

                Spacer()

                // Navigation
                HStack(spacing: 20) {
                    Button {
                        withAnimation(.spring) {
                            currentStep = max(0, currentStep - 1)
                        }
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.bordered)
                    .disabled(currentStep == 0)

                    if currentStep < steps.count - 1 {
                        Button {
                            withAnimation(.spring) {
                                currentStep = min(steps.count - 1, currentStep + 1)
                            }
                        } label: {
                            Label("Next", systemImage: "chevron.right")
                                .labelStyle(.titleAndIcon)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            dismiss()
                        } label: {
                            Label("Done!", systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sheet(isPresented: $showAllSteps) {
            AllStepsView(steps: steps, currentStep: $currentStep)
        }
    }
}

// MARK: - All Steps Overview

struct AllStepsView: View {
    @Environment(\.dismiss) var dismiss
    let steps: [String]
    @Binding var currentStep: Int

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    Button {
                        currentStep = index
                        dismiss()
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.subheadline.bold())
                                .foregroundStyle(index == currentStep ? .white : Color.accentColor)
                                .frame(width: 28, height: 28)
                                .background(
                                    index == currentStep ? Color.accentColor : Color.accentColor.opacity(0.1),
                                    in: Circle()
                                )
                            Text(step)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("All Steps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
