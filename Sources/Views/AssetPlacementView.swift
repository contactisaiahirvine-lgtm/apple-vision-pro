import SwiftUI

struct AssetPlacementView: View {
    @EnvironmentObject var gameManager: GameManager
    @ObservedObject var assetManager: AssetManager
    @ObservedObject var placementManager: PlacementManager

    @State private var selectedCategory: AssetCategory = .primitive
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 20) {
            Text("3D Asset Placement")
                .font(.title2)
                .bold()

            // Placement Status
            if placementManager.placementMode != .none {
                VStack(spacing: 10) {
                    Text("Placement Mode Active")
                        .font(.headline)
                        .foregroundColor(.green)

                    if case .placing(let assetName) = placementManager.placementMode {
                        Text("Placing: \(assetName)")
                            .font(.caption)
                    }

                    Button("Cancel Placement") {
                        placementManager.cancelPlacement()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(10)
            }

            // Category Selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(AssetCategory.allCases, id: \.self) { category in
                        Button(category.rawValue) {
                            selectedCategory = category
                        }
                        .buttonStyle(.bordered)
                        .tint(selectedCategory == category ? .blue : .gray)
                    }
                }
            }

            // Asset Grid
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 15) {
                    ForEach(filteredAssets) { asset in
                        AssetCard(asset: asset) {
                            Task {
                                await placementManager.startPlacement(assetName: asset.id)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 300)

            Divider()

            // Placed Objects List
            if !placementManager.placedObjects.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Placed Objects (\(placementManager.placedObjects.count))")
                        .font(.headline)

                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(placementManager.placedObjects) { object in
                                PlacedObjectRow(object: object,
                                              isSelected: placementManager.selectedObject?.id == object.id,
                                              onSelect: {
                                    placementManager.selectedObject = object
                                },
                                              onDelete: {
                                    placementManager.deleteObject(object)
                                })
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }

            // Object Controls (when selected)
            if let selected = placementManager.selectedObject {
                VStack(spacing: 10) {
                    Text("Selected: \(selected.assetName)")
                        .font(.headline)

                    HStack(spacing: 15) {
                        // Rotate buttons
                        Button {
                            placementManager.rotateObject(selected, by: .pi / 4)
                        } label: {
                            Image(systemName: "rotate.left")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            placementManager.rotateObject(selected, by: -.pi / 4)
                        } label: {
                            Image(systemName: "rotate.right")
                        }
                        .buttonStyle(.bordered)

                        // Scale buttons
                        Button {
                            placementManager.scaleObject(selected, by: 1.2)
                        } label: {
                            Image(systemName: "plus.magnifyingglass")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            placementManager.scaleObject(selected, by: 0.8)
                        } label: {
                            Image(systemName: "minus.magnifyingglass")
                        }
                        .buttonStyle(.bordered)

                        // Delete button
                        Button {
                            showDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(10)
                .alert("Delete Object", isPresented: $showDeleteConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive) {
                        placementManager.deleteObject(selected)
                    }
                } message: {
                    Text("Are you sure you want to delete this object?")
                }
            }

            // Clear All button
            if !placementManager.placedObjects.isEmpty {
                Button("Clear All Objects") {
                    placementManager.clearAll()
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding()
    }

    private var filteredAssets: [AssetDefinition] {
        assetManager.availableAssets.filter { $0.category == selectedCategory }
    }
}

// MARK: - Asset Card

struct AssetCard: View {
    let asset: AssetDefinition
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                // Color preview
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(asset.previewColor))
                    .frame(height: 60)
                    .overlay(
                        Image(systemName: iconForCategory(asset.category))
                            .font(.title)
                            .foregroundColor(.white)
                    )

                Text(asset.name)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private func iconForCategory(_ category: AssetCategory) -> String {
        switch category {
        case .primitive:
            return "cube.fill"
        case .decoration:
            return "star.fill"
        case .furniture:
            return "house.fill"
        case .character:
            return "person.fill"
        case .environment:
            return "tree.fill"
        case .game:
            return "gamecontroller.fill"
        case .custom:
            return "square.stack.3d.up.fill"
        }
    }
}

// MARK: - Placed Object Row

struct PlacedObjectRow: View {
    let object: PlacedObject
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(object.assetName)
                    .font(.subheadline)
                    .bold()

                Text("ID: \(object.id)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Pos: (\(String(format: "%.2f", object.position.x)), \(String(format: "%.2f", object.position.y)), \(String(format: "%.2f", object.position.z)))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(8)
        .background(isSelected ? Color.blue.opacity(0.2) : Color.clear)
        .cornerRadius(8)
        .onTapGesture {
            onSelect()
        }
    }
}

// MARK: - Preview

#Preview {
    let assetManager = AssetManager()
    let placementManager = PlacementManager()

    return AssetPlacementView(assetManager: assetManager, placementManager: placementManager)
        .environmentObject(GameManager())
}
