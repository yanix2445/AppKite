//
//  AppKiteTests.swift
//  AppKiteTests
//
//  Created by Yanis HARRAT on 07/11/2026.
//

import Foundation
import Testing

struct AppKiteTests {
    @Test func hostAppIsMenuBarOnly() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool == true)
    }
}
