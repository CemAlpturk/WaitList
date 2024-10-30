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

            Divider()

            HStack {
                Button(action: {
                    showingAddProduct.toggle()
                }) {
                    Label("Add Product", systemImage: "plus")
                        .fontWeight(.semibold)
                }
                .sheet(isPresented: $showingAddProduct) {
                    AddProductView(viewModel: viewModel)
                }

                Spacer()

                Button(action: {
                    quitApp()
                }) {
                    Label("Quit App", systemImage: "power")
                        .foregroundColor(.red)
                        .fontWeight(.semibold)
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
