// Name: Snapshot
// Icon: camera.fill
// Tint: indigo
// Covers: Camera

import SwiftUI
import UIKit
import AVFoundation

// The camera as models write it: UIImagePickerController with .camera in a
// UIViewControllerRepresentable whose Coordinator is the delegate. Shelf asks
// for the camera first; on the simulator a fake camera stands in.

struct CameraView: UIViewControllerRepresentable {
    var source: UIImagePickerController.SourceType
    var onPhoto: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = source
        if source == .camera {
            picker.cameraDevice = .rear
            picker.cameraCaptureMode = .photo
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView

        init(_ parent: CameraView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onPhoto(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct ContentView: View {
    @State private var photos: [UIImage] = []
    @State private var showingCamera = false
    @State private var access = "Not asked"

    var hasCamera: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let last = photos.last {
                    Image(uiImage: last)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    ContentUnavailableView("No photos yet", systemImage: "camera", description: Text("Take one with the button below."))
                }
                Text("\(photos.count) taken · camera \(access)")
                    .foregroundStyle(.secondary)
                Button {
                    showingCamera = true
                } label: {
                    Label(hasCamera ? "Take Photo" : "Choose Photo", systemImage: "camera.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle("Snapshot")
            .sheet(isPresented: $showingCamera) {
                CameraView(source: hasCamera ? .camera : .photoLibrary) { image in
                    photos.append(image)
                }
                .ignoresSafeArea()
            }
            .task {
                switch AVCaptureDevice.authorizationStatus(for: .video) {
                case .authorized: access = "allowed"
                case .denied, .restricted: access = "off"
                default: access = "not asked"
                }
            }
        }
    }
}
