//
//  TopPanel.swift
//  VeloPath
//
//  Created by Ondřej Vít on 12.10.2025.
//

import SwiftUI

struct TopPanel: View {
    var body: some View {
        VStack {
            HStack {
                HStack(spacing: 8) {
                    Image("VeloPath")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 25, height: 25)
                    Text("VeloPath")
                        .font(.title2.bold())
                        .foregroundColor(Color(red: 52/255, green: 189/255, blue: 253/255))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 12)

            Spacer()
        }
    }
}
