//
//  SplashView.swift
//  VeloPath
//
//  Created by Ondřej Vít on 08.10.2025.
//

import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                Image("VeloPath")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160, height: 160)
                    .shadow(radius: 10)
                
                Text("VeloPath")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(Color(red: 52/255, green: 189/255, blue: 253/255))
                
                ProgressView("Načítám silnice…")
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .padding(.top, 10)
            }
        }
    }
}
