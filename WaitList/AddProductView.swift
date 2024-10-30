//
//  AddProductView.swift
//  WaitList
//
//  Created by Cem Alptürk on 2024-10-30.
//

import SwiftUI

struct AddProductView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var viewModel: ProductViewModel

    @State private var productName: String = ""
    @State private var daysUntilDeadline: String = "14"

    var body: some View {
        VStack(spacing: 20) {
            Text("Add a New Product")
                .font(.headline)

            TextField("Product Name", text: $productName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            TextField("Days Until Deadline", text: $daysUntilDeadline)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
                //.keyboardType(.numberPad)

            Button(action: {
                if let days = Int(daysUntilDeadline), !productName.isEmpty {
                    viewModel.addProduct(name: productName, daysUntilDeadline: days)
                    presentationMode.wrappedValue.dismiss()
                }
            }) {
                Text("Add")
            }
            .disabled(productName.isEmpty || Int(daysUntilDeadline) == nil)
            .padding()

            Spacer()
        }
        .padding()
        .frame(width: 300, height: 200)
    }
}
