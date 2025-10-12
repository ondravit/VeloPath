//
//  TopPanel.swift
//  VeloPath
//
//  Created by Ondřej Vít on 12.10.2025.
//

import SwiftUI

struct TopPanel: View {
    var body: some View {
        // 🧭 Top bar (logo + menu)
        VStack {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "bicycle")
                        .foregroundColor(Color(red: 52/255, green: 189/255, blue: 253/255))
                        .font(.title2.bold())
                    Text("VeloPath")
                        .font(.title2.bold())
                        .foregroundColor(Color(red: 52/255, green: 189/255, blue: 253/255))
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 12)

            Spacer()
        }
    }
}

