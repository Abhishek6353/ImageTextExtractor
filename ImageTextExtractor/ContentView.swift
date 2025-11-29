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
    let text: String
}

struct ContentView: View {
    @State private var uiImage: UIImage? = nil
    @State private var showingPicker = false
    @State private var recognized: [RecognizedText] = []
    @State private var showingResults = false
    @State private var alertMessage: AlertMessage? = nil
    @State private var liveMode: Bool = false

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                ZStack {
                    Color(UIColor.systemBackground)
                        .edgesIgnoringSafeArea(.all)

                    if let img = uiImage {
                        GeometryReader { geo in
                            ImageViewWithOverlays(image: img, recognizedGroups: groupedText, containerSize: geo.size, liveMode: liveMode, onTextTap: { textItem in
                                copyToClipboard(textItem.combinedString)
                            }, onDismissLive: {
                                liveMode = false
                            })
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 120, height: 120)
                                .foregroundColor(.secondary)
                            Text("Select an image to scan text")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }

                HStack(spacing: 16) {
                    Button(action: { showingPicker = true }) {
                        Label("Select Image", systemImage: "photo")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: {
                        liveMode = true
                        scanImage()
                    }) {
                        Label("Scan", systemImage: "text.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(uiImage == nil)
                }
                .padding([.horizontal, .bottom])
            }
            .navigationTitle("Get Image Text")
            .sheet(isPresented: $showingPicker) {
                PhotoPicker(image: $uiImage)
            }
            .onChange(of: uiImage) { _ in
                // Clear previous scan results when new image is selected
                recognized.removeAll()
                liveMode = false
            }
            .sheet(isPresented: $showingResults) {
                ResultsSheet(recognized: recognized, onCopyAll: copyAll)
            }
            .alert(item: $alertMessage) { msg in
                Alert(title: Text(msg.text))
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
        alertMessage = AlertMessage(text: "Copied: \(text)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            alertMessage = nil
        }
    }

    private func copyAll() {
        let all = recognized.map { $0.string }.joined(separator: "\n")
        UIPasteboard.general.string = all
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        alertMessage = AlertMessage(text: "Copied all text")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            alertMessage = nil
        }
    }

    private func scanImage() {
        recognized.removeAll()
        guard let img = uiImage, let cg = img.cgImage else { return }

        let request = VNRecognizeTextRequest { request, error in
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

            DispatchQueue.main.async {
                self.recognized = results
                if results.isEmpty {
                    self.showingResults = !results.isEmpty
                }
            }
        }

        request.recognitionLevel = .accurate
        request.recognitionLanguages = [Locale.current.identifier]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cg, orientation: cgImagePropertyOrientation(from: uiImage!), options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                print("failed: \(error)")
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
        @unknown default:
            return .up
        }
    }
    
    // Group nearby text boxes together using recursive clustering
    private func groupNearbyText(_ items: [RecognizedText]) -> [GroupedText] {
        guard !items.isEmpty else { return [] }
        
        var groups: [[RecognizedText]] = []
        var used = Set<UUID>()
        
        for item in items {
            if used.contains(item.id) { continue }
            
            var group = [item]
            used.insert(item.id)
            
            // Recursively find all connected items
            var changed = true
            while changed {
                changed = false
                
                for other in items {
                    if used.contains(other.id) { continue }
                    
                    // Check if other is close to ANY item in the current group
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
        
        // Convert groups to GroupedText
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
        
        // Calculate vertical overlap
        let verticalOverlap = max(0, min(box1.maxY, box2.maxY) - max(box1.minY, box2.minY))
        let avgHeight = (box1.height + box2.height) / 2
        
        // Calculate horizontal gap (distance between boxes)
        let horizontalGap: CGFloat
        if box1.maxX < box2.minX {
            horizontalGap = box2.minX - box1.maxX
        } else if box2.maxX < box1.minX {
            horizontalGap = box1.minX - box2.maxX
        } else {
            horizontalGap = 0 // overlapping
        }
        
        // More aggressive grouping: group if on same line and reasonably close
        let onSameLine = verticalOverlap > avgHeight * 0.5 // 50% vertical overlap
        let closeEnough = horizontalGap < avgHeight * 1.5 // within 1.5x height distance
        
        return onSameLine && closeEnough
    }
}

// MARK: - Image view with overlays
struct ImageViewWithOverlays: View {
    let image: UIImage
    let recognizedGroups: [GroupedText]
    let containerSize: CGSize
    let liveMode: Bool
    let onTextTap: (GroupedText) -> Void
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

                // overlay recognized text highlight boxes
                if liveMode {
                    // Create a mask effect: darken everything except text areas
                    Canvas { context, size in
                        // Draw dark overlay
                        context.fill(
                            Path(CGRect(origin: .zero, size: size)),
                            with: .color(Color.black.opacity(0.5))
                        )
                        
                        // Cut out holes for text areas (blend mode to remove overlay)
                        context.blendMode = .destinationOut
                        
                        for item in recognizedGroups {
                            let rect = convertNormalizedRect(item.box, imageSize: imgSize, displaySize: fit, offset: offset)
                            let expandedRect = CGRect(
                                x: rect.origin.x - 4,
                                y: rect.origin.y - 2,
                                width: rect.width + 8,
                                height: rect.height + 4
                            )
                            let path = Path(roundedRect: expandedRect, cornerRadius: 6)
                            context.fill(path, with: .color(.white))
                        }
                    }
                    .allowsHitTesting(false)
                    
                    // Invisible tap targets over text areas
                    ForEach(recognizedGroups) { item in
                        let rect = convertNormalizedRect(item.box, imageSize: imgSize, displaySize: fit, offset: offset)
                        
                        Button(action: {
                            onTextTap(item)
                        }) {
                            Color.clear
                        }
                        .frame(width: max(rect.width + 8, 30), height: max(rect.height + 4, 18))
                        .position(x: rect.midX, y: rect.midY)
                    }

                    // live-mode floating controls
                    if !recognizedGroups.isEmpty {
                        VStack {
                            Spacer()
                            HStack(alignment: .bottom, spacing: 0) {
                                // Copy All button - bottom left
                                Button(action: {
                                    let all = recognizedGroups.map { $0.combinedString }.joined(separator: "\n")
                                    UIPasteboard.general.string = all
                                    let generator = UINotificationFeedbackGenerator()
                                    generator.notificationOccurred(.success)
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 16))
                                        Text("Copy All")
                                            .font(.system(size: 16, weight: .medium))
                                    }
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(VisualEffectBlur(blurStyle: .systemThinMaterial))
                                    .cornerRadius(22)
                                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                                }
                                .padding(.leading, 20)
                                .padding(.bottom, 20)

                                Spacer()
                                
                                // Scan button - bottom right
                                Button(action: {
                                    onDismissLive()
                                }) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.blue)
                                            .frame(width: 60, height: 60)
                                            .shadow(color: .blue.opacity(0.4), radius: 8, x: 0, y: 4)
                                        Image(systemName: "text.viewfinder")
                                            .foregroundColor(.white)
                                            .font(.system(size: 24, weight: .semibold))
                                    }
                                }
                                .padding(.trailing, 20)
                                .padding(.bottom, 20)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

struct VisualEffectBlur: UIViewRepresentable {
    var blurStyle: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        return UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: blurStyle)
    }
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
                    Text("No text detected")
                } else {
                    Section(header: Text("Detected Text")) {
                        ForEach(recognized) { item in
                            HStack {
                                Text(item.string)
                                    .lineLimit(nil)
                                Spacer()
                                Button(action: {
                                    UIPasteboard.general.string = item.string
                                    let generator = UINotificationFeedbackGenerator()
                                    generator.notificationOccurred(.success)
                                }) {
                                    Image(systemName: "doc.on.doc")
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Scan Results")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Copy All") { onCopyAll() }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
