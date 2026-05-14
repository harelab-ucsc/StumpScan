//
//  ContentView.swift
//  StumpScan
//
//  Created by Derick Mathews on 5/13/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        ArucoDetectionView()
            .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}
