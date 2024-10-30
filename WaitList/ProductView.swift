//
//  ProductView.swift
//  WaitList
//
//  Created by Cem Alptürk on 2024-10-30.
//

import Foundation
import UserNotifications
import Combine

class ProductViewModel: ObservableObject {
    @Published var products: [Product] = []

    private var timer: AnyCancellable?

    init() {
        loadProducts()
        scheduleNotifications()
        startTimer()
    }

    func startTimer() {
        timer = Timer.publish(every: 86400, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.removeExpiredProducts()
            }
    }

    func addProduct(name: String, daysUntilDeadline: Int) {
        let deadline = Calendar.current.date(byAdding: .day, value: daysUntilDeadline, to: Date())!
        let product = Product(id: UUID(), name: name, deadline: deadline)
        products.append(product)
        saveProducts()
        scheduleNotification(for: product)
    }

    func removeProduct(at offsets: IndexSet) {
        let removedProducts = offsets.map { products[$0] }
        products.remove(atOffsets: offsets)
        saveProducts()
        removeNotifications(for: removedProducts)
    }

    func saveProducts() {
        if let data = try? JSONEncoder().encode(products) {
            UserDefaults.standard.set(data, forKey: "products")
        }
    }

    func loadProducts() {
        if let data = UserDefaults.standard.data(forKey: "products"),
           let savedProducts = try? JSONDecoder().decode([Product].self, from: data) {
            products = savedProducts.filter { $0.isActive }
        }
    }

    func scheduleNotifications() {
        for product in products {
            scheduleNotification(for: product)
        }
    }

    func scheduleNotification(for product: Product) {
            let content = UNMutableNotificationContent()
            content.title = "Re-evaluate your purchase"
            content.body = "It's time to re-evaluate buying '\(product.name)'."

            // Add the image attachment
            if let imageURL = Bundle.main.url(forResource: "Waitlist", withExtension: "png") {
                do {
                    let attachment = try UNNotificationAttachment(identifier: "imageAttachment", url: imageURL, options: nil)
                    content.attachments = [attachment]
                } catch {
                    print("Error attaching image to notification: \(error)")
                }
            }

            let triggerDate = Calendar.current.dateComponents([.year, .month, .day], from: product.deadline)
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)

            let request = UNNotificationRequest(identifier: product.id.uuidString, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }

    func removeNotifications(for products: [Product]) {
        let identifiers = products.map { $0.id.uuidString }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeExpiredProducts() {
        products = products.filter { $0.isActive }
        saveProducts()
    }

    deinit {
        timer?.cancel()
    }
}
