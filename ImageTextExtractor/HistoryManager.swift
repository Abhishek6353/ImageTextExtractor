//
//  HistoryManager.swift
//  ImageTextExtractor
//
//  Created by Apple on 24/12/26.
//

import Foundation
import SwiftUI

struct HistoryItem: Identifiable, Codable {
    let id: UUID
    let date: Date
    let text: String
    
    init(text: String) {
        self.id = UUID()
        self.date = Date()
        self.text = text
    }
}

class HistoryManager: ObservableObject {
    @Published var history: [HistoryItem] = []
    private let key = "scan_history_key"
    
    init() {
        load()
    }
    
    func add(text: String) {
        let newItem = HistoryItem(text: text)
        history.insert(newItem, at: 0)
        // Keep only last 50 items
        if history.count > 50 {
            history.removeLast()
        }
        save()
    }
    
    func delete(at offsets: IndexSet) {
        history.remove(atOffsets: offsets)
        save()
    }
    
    func clear() {
        history.removeAll()
        save()
    }
    
    private func save() {
        if let encoded = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            history = decoded
        }
    }
}
