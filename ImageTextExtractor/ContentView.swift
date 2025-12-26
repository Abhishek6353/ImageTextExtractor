//
//  ContentView.swift
//  ImageTextExtractor
//
//  Created by Apple on 29/11/25.
//

import SwiftUI
import PhotosUI
import Vision
import UIKit

// MARK: - Models
struct RecognizedText: Identifiable {
    let id = UUID()
    let string: String
    let box: CGRect // normalized bounding box (0-1) relative to image
}

struct GroupedText: Identifiable {
    let id = UUID()
    let strings: [String]
    let box: CGRect // combined bounding box
    
    var combinedString: String {
        strings.joined(separator: " ")
    }
}

struct AlertMessage: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

// MARK: - Premium Button Style
struct PremiumButtonStyle: ButtonStyle {
    var primary: Bool = true
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .padding(.vertical, 14)
            .padding(.horizontal, 24)
            .background(
                ZStack {
                    if primary {
                        LinearGradient(gradient: Gradient(colors: [Color.blue, Color.purple]), startPoint: .topLeading, endPoint: .bottomTrailing)
                    } else {
                        Color(UIColor.secondarySystemBackground)
                    }
                }
            )
            .foregroundColor(primary ? .white : .primary)
            .cornerRadius(16)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            .shadow(color: primary ? Color.blue.opacity(0.3) : Color.clear, radius: 10, x: 0, y: 5)
    }
}

// MARK: - Main View
struct ContentView: View {
    @StateObject private var historyManager = HistoryManager()
    @State private var uiImage: UIImage? = nil
    @State private var showingPicker = false
    @State private var showingCamera = false
    @State private var recognized: [RecognizedText] = []
    @State private var showingResults = false
    @State private var showingHistory = false
    @State private var alertMessage: AlertMessage? = nil
    @State private var liveMode: Bool = false
    @State private var isScanning: Bool = false
    
    // Animation states
    @State private var animateItems = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background Gradient
                Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 20) {
                    // Image Container
                    ZStack {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color(UIColor.secondarySystemBackground))
                            .shadow(color: Color.black.opacity(0.05), radius: 15, x: 0, y: 10)
                        
                        if let img = uiImage {
                            GeometryReader { geo in
                                ImageViewWithOverlays(
                                    image: img,
                                    recognizedGroups: groupedText,
                                    containerSize: geo.size,
                                    liveMode: liveMode,
                                    onTextTap: { textItem in
                                        copyToClipboard(textItem.combinedString)
                                    },
                                    onCopyAll: { text in
                                        copyToClipboard(text)
                                    },
                                    onDismissLive: {
                                        withAnimation(.spring()) {
                                            liveMode = false
                                        }
                                    }
                                )
                                .cornerRadius(24)
                            }
                        } else {
                            VStack(spacing: 24) {
                                ZStack {
                                    Circle()
                                        .fill(LinearGradient(gradient: Gradient(colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)]), startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 140, height: 140)
                                    
                                    Image(systemName: "doc.text.viewfinder")
                                        .font(.system(size: 60, weight: .light))
                                        .foregroundStyle(
                                            LinearGradient(gradient: Gradient(colors: [Color.blue, Color.purple]), startPoint: .topLeading, endPoint: .bottomTrailing)
                                        )
                                }
                                
                                VStack(spacing: 8) {
                                    Text("Ready to Scan")
                                        .font(.system(size: 24, weight: .bold, design: .rounded))
                                    Text("Select or take a photo to extract text effortlessly.")
                                        .font(.system(size: 16))
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 40)
                                }
                            }
                            .offset(y: animateItems ? 0 : 20)
                            .opacity(animateItems ? 1 : 0)
                        }
                        
                        if isScanning {
                            ZStack {
                                Color.black.opacity(0.3)
                                    .cornerRadius(24)
                                VStack(spacing: 16) {
                                    ProgressView()
                                        .scaleEffect(1.5)
                                        .tint(.white)
                                    Text("Extracting Text...")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            }
                            .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        if uiImage != nil {
                            Button(action: {
                                withAnimation(.spring()) {
                                    liveMode = true
                                    scanImage()
                                }
                            }) {
                                HStack {
                                    Image(systemName: "sparkles")
                                    Text("Start Smart Scan")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PremiumButtonStyle())
                            .disabled(isScanning)
                        }
                        
                        HStack(spacing: 12) {
                            Button(action: { showingCamera = true }) {
                                HStack {
                                    Image(systemName: "camera.fill")
                                    Text("Camera")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PremiumButtonStyle(primary: uiImage == nil))
                            
                            Button(action: { showingPicker = true }) {
                                HStack {
                                    Image(systemName: "photo.fill")
                                    Text("Library")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PremiumButtonStyle(primary: false))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Text Extractor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingHistory = true }) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 18, weight: .semibold))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !recognized.isEmpty {
                        Button(action: { showingResults = true }) {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.system(size: 18, weight: .semibold))
                        }
                    }
                }
            }
            .sheet(isPresented: $showingPicker) {
                PhotoPicker(image: $uiImage)
            }
            .sheet(isPresented: $showingCamera) {
                CameraPicker(image: $uiImage)
            }
            .sheet(isPresented: $showingHistory) {
                HistoryView(historyManager: historyManager)
            }
            .onChange(of: uiImage) { _ in
                recognized.removeAll()
                liveMode = false
            }
            .sheet(isPresented: $showingResults) {
                ResultsSheet(recognized: recognized, onCopyAll: copyAll)
            }
            .alert(item: $alertMessage) { msg in
                Alert(
                    title: Text(msg.title),
                    message: Text(msg.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.8)) {
                    animateItems = true
                }
            }
        }
    }
    
    private var groupedText: [GroupedText] {
        groupNearbyText(recognized)
    }

    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        let preview = text.count > 60 ? String(text.prefix(60)) + "..." : text
        
        withAnimation {
            alertMessage = AlertMessage(title: "Copied to Clipboard", message: preview)
        }
        
        // Auto-dismiss after 2 seconds if desired, but Alert usually needs manual dismissal
        // To be safe with system Alert, we don't force nil it unless we use a custom HUD.
    }

    private func copyAll() {
        let all = recognized.map { $0.string }.joined(separator: "\n")
        UIPasteboard.general.string = all
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        let preview = all.count > 100 ? String(all.prefix(100)) + "..." : all
        
        alertMessage = AlertMessage(title: "All Text Copied", message: preview)
    }

    private func scanImage() {
        guard let img = uiImage, let cg = img.cgImage else { return }
        
        withAnimation {
            isScanning = true
            recognized.removeAll()
        }

        let request = VNRecognizeTextRequest { request, error in
            DispatchQueue.main.async {
                self.isScanning = false
                if let err = error {
                    print("Vision error: \(err)")
                    return
                }
                var results: [RecognizedText] = []
                for r in request.results as? [VNRecognizedTextObservation] ?? [] {
                    guard let candidate = r.topCandidates(1).first else { continue }
                    let text = candidate.string
                    let box = r.boundingBox
                    results.append(RecognizedText(string: text, box: box))
                }

                withAnimation(.spring()) {
                    self.recognized = results
                    if !results.isEmpty {
                        let combined = results.map { $0.string }.joined(separator: " ")
                        historyManager.add(text: combined)
                    }
                }
            }
        }

        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"] // Defaulting to English, can be made dynamic
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cg, orientation: cgImagePropertyOrientation(from: uiImage!), options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    self.isScanning = false
                    print("failed: \(error)")
                }
            }
        }
    }

    private func cgImagePropertyOrientation(from image: UIImage) -> CGImagePropertyOrientation {
        switch image.imageOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
    
    private func groupNearbyText(_ items: [RecognizedText]) -> [GroupedText] {
        guard !items.isEmpty else { return [] }
        var groups: [[RecognizedText]] = []
        var used = Set<UUID>()
        
        for item in items {
            if used.contains(item.id) { continue }
            var group = [item]
            used.insert(item.id)
            var changed = true
            while changed {
                changed = false
                for other in items {
                    if used.contains(other.id) { continue }
                    for groupItem in group {
                        if shouldGroup(groupItem, other) {
                            group.append(other)
                            used.insert(other.id)
                            changed = true
                            break
                        }
                    }
                }
            }
            groups.append(group)
        }
        
        return groups.map { group in
            let sortedGroup = group.sorted { $0.box.minX < $1.box.minX }
            let strings = sortedGroup.map { $0.string }
            let combinedBox = sortedGroup.reduce(sortedGroup[0].box) { result, item in
                result.union(item.box)
            }
            return GroupedText(strings: strings, box: combinedBox)
        }
    }
    
    private func shouldGroup(_ item1: RecognizedText, _ item2: RecognizedText) -> Bool {
        let box1 = item1.box
        let box2 = item2.box
        let verticalOverlap = max(0, min(box1.maxY, box2.maxY) - max(box1.minY, box2.minY))
        let avgHeight = (box1.height + box2.height) / 2
        let horizontalGap: CGFloat
        if box1.maxX < box2.minX {
            horizontalGap = box2.minX - box1.maxX
        } else if box2.maxX < box1.minX {
            horizontalGap = box1.minX - box2.maxX
        } else {
            horizontalGap = 0
        }
        return (verticalOverlap > avgHeight * 0.5) && (horizontalGap < avgHeight * 1.5)
    }
}

// MARK: - Image view with overlays
struct ImageViewWithOverlays: View {
    let image: UIImage
    let recognizedGroups: [GroupedText]
    let containerSize: CGSize
    let liveMode: Bool
    let onTextTap: (GroupedText) -> Void
    let onCopyAll: (String) -> Void
    let onDismissLive: () -> Void

    var body: some View {
        GeometryReader { geo in
            let imgSize = CGSize(width: image.size.width, height: image.size.height)
            let fit = aspectFitSize(contentSize: imgSize, containerSize: geo.size)
            let offset = CGPoint(x: (geo.size.width - fit.width)/2, y: (geo.size.height - fit.height)/2)

            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: fit.width, height: fit.height)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)

                if liveMode {
                    // Glassmorphism Overlay Mask
                    Canvas { context, size in
                        context.fill(
                            Path(CGRect(origin: .zero, size: size)),
                            with: .color(Color.black.opacity(0.4))
                        )
                        
                        context.blendMode = .destinationOut
                        
                        for item in recognizedGroups {
                            let rect = convertNormalizedRect(item.box, imageSize: imgSize, displaySize: fit, offset: offset)
                            let expandedRect = CGRect(
                                x: rect.origin.x - 4,
                                y: rect.origin.y - 2,
                                width: rect.width + 8,
                                height: rect.height + 4
                            )
                            let path = Path(roundedRect: expandedRect, cornerRadius: 8)
                            context.fill(path, with: .color(.white))
                        }
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    
                    // Interaction Layer
                    ForEach(recognizedGroups) { item in
                        let rect = convertNormalizedRect(item.box, imageSize: imgSize, displaySize: fit, offset: offset)
                        
                        TextHighlightView(rect: rect) {
                            onTextTap(item)
                        }
                    }

                    // Controls
                    VStack {
                        Spacer()
                        HStack {
                            Button(action: {
                                let all = recognizedGroups.map { $0.combinedString }.joined(separator: "\n")
                                onCopyAll(all)
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.on.doc.fill")
                                    Text("Copy All")
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(BlurView(style: .systemThinMaterial).cornerRadius(20))
                                .shadow(color: .black.opacity(0.1), radius: 5)
                            }
                            .padding(.leading, 20)
                            
                            Spacer()
                            
                            Button(action: onDismissLive) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 50, height: 50)
                                    .background(Color.red.opacity(0.8).cornerRadius(25))
                                    .shadow(color: .red.opacity(0.3), radius: 5)
                            }
                            .padding(.trailing, 20)
                        }
                        .padding(.bottom, 30)
                    }
                }
            }
        }
    }

    private func aspectFitSize(contentSize: CGSize, containerSize: CGSize) -> CGSize {
        let scale = min(containerSize.width / contentSize.width, containerSize.height / contentSize.height)
        return CGSize(width: contentSize.width * scale, height: contentSize.height * scale)
    }

    private func convertNormalizedRect(_ normalizedRect: CGRect, imageSize: CGSize, displaySize: CGSize, offset: CGPoint) -> CGRect {
        let x = normalizedRect.origin.x * displaySize.width + offset.x
        let y = (1.0 - normalizedRect.origin.y - normalizedRect.height) * displaySize.height + offset.y
        let w = normalizedRect.width * displaySize.width
        let h = normalizedRect.height * displaySize.height
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

struct TextHighlightView: View {
    let rect: CGRect
    let action: () -> Void
    @State private var isAnimating = false
    
    var body: some View {
        Button(action: {
            action()
            withAnimation(.easeInOut(duration: 0.1)) {
                isAnimating = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isAnimating = false
            }
        }) {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white, lineWidth: 2)
                .background(Color.white.opacity(isAnimating ? 0.4 : 0.05))
                .cornerRadius(8)
        }
        .frame(width: rect.width + 8, height: rect.height + 4)
        .position(x: rect.midX, y: rect.midY)
    }
}

struct BlurView: UIViewRepresentable {
    var style: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

// MARK: - Photo Picker wrapper
struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        init(_ parent: PhotoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let item = results.first else { return }
            if item.itemProvider.canLoadObject(ofClass: UIImage.self) {
                item.itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                    if let img = object as? UIImage {
                        DispatchQueue.main.async {
                            self.parent.image = img
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Results sheet
struct ResultsSheet: View {
    let recognized: [RecognizedText]
    let onCopyAll: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                if recognized.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "text.badge.xmark")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        Text("No text detected in this image.")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
                    .padding(.top, 40)
                } else {
                    Section {
                        ForEach(recognized) { item in
                            HStack(spacing: 16) {
                                Text(item.string)
                                    .font(.system(size: 16, design: .rounded))
                                    .lineLimit(nil)
                                
                                Spacer()
                                
                                Button(action: {
                                    UIPasteboard.general.string = item.string
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }) {
                                    Image(systemName: "doc.on.doc")
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 8)
                        }
                    } header: {
                        Text("\(recognized.count) Snippets Found")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Extracted Text")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                        .fontWeight(.medium)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button(action: { shareText(recognized.map { $0.string }.joined(separator: "\n")) }) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Button("Copy All") { onCopyAll() }
                            .fontWeight(.bold)
                    }
                }
            }
        }
    }
    
    private func shareText(_ text: String) {
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(av, animated: true, completion: nil)
        }
    }
}

// MARK: - History View
struct HistoryView: View {
    @ObservedObject var historyManager: HistoryManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                if historyManager.history.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        Text("No scan history yet.")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
                    .padding(.top, 40)
                } else {
                    ForEach(historyManager.history) { item in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(item.date, style: .date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(item.text)
                                .font(.system(size: 14))
                                .lineLimit(3)
                                .foregroundColor(.primary)
                            
                            HStack {
                                Spacer()
                                Button(action: {
                                    UIPasteboard.general.string = item.text
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }) {
                                    Label("Copy", systemImage: "doc.on.doc")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(8)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .onDelete(perform: historyManager.delete)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !historyManager.history.isEmpty {
                        Button("Clear") {
                            historyManager.clear()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
