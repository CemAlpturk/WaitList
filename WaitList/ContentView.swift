//
//  ContentView.swift
//  WaitList
//
//  Created by Cem Alptürk on 2024-10-30.
//

import SwiftUI

struct ContentView: View {
    @StateObject var viewModel = ProductViewModel()
    @State private var showingAddProduct = false

    var body: some View {
        VStack {
            List {
                ForEach(viewModel.products) { product in
                    HStack {
                        Text(product.name)
                        Spacer()
                        Text("\(product.daysLeft) days left")
                            .foregroundColor(.gray)
                        Button(action: {
                            deleteProduct(product)
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .padding(.leading, 5)
                    }
                }
            }
            .frame(minWidth: 300, minHeight: 300)

            Divider() // Adds a visual separator between the list and buttons

            HStack {
                Button(action: {
                    showingAddProduct.toggle()
                }) {
                    Text("Add Product")
                }
                .sheet(isPresented: $showingAddProduct) {
                    AddProductView(viewModel: viewModel)
                }

                Spacer()

                Button(action: {
                    quitApp()
                }) {
                    Text("Quit App")
                        .foregroundColor(.red)
                }
            }
            .padding()
        }
    }

    private func deleteProduct(_ product: Product) {
        if let index = viewModel.products.firstIndex(where: { $0.id == product.id }) {
            viewModel.removeProduct(at: IndexSet(integer: index))
        }
    }

    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
