//
//  ProfileView.swift
//  Passepartout
//
//  Created by Davide De Rosa on 2/6/22.
//  Copyright (c) 2022 Davide De Rosa. All rights reserved.
//
//  https://github.com/passepartoutvpn
//
//  This file is part of Passepartout.
//
//  Passepartout is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Passepartout is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with Passepartout.  If not, see <http://www.gnu.org/licenses/>.
//

import SwiftUI
import PassepartoutCore

struct ProfileView: View {
    enum ModalType: Int, Identifiable {
        case shortcuts
        
        case rename
        
        case paywallShortcuts

        case paywallNetworkSettings
        
        case paywallTrustedNetworks

        var id: Int {
            return rawValue
        }
    }

    @Environment(\.presentationMode) private var presentationMode
    
    @ObservedObject private var profileManager: ProfileManager
    
    private let header: Profile.Header
    
    private var isExisting: Bool {
        profileManager.isExistingProfile(withId: header.id)
    }

    @State private var modalType: ModalType?
    
    @State private var isLoaded = false
    
    init(header: Profile.Header?) {
        let profileManager: ProfileManager = .shared
        
        self.profileManager = profileManager
        self.header = header ?? profileManager.activeHeader ?? Profile.placeholder.header
    }

    var body: some View {
        debugChanges()
        return Group {
            if isExisting {
                mainView
            } else {
                welcomeView
            }
        }.toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                ShortcutsItem(
                    modalType: $modalType
                ).disabled(!isExisting)

                RenameItem(
                    currentProfile: profileManager.currentProfile,
                    modalType: $modalType
                ).disabled(!isExisting)
            }
        }.sheet(item: $modalType, content: presentedModal)
        .onAppear(perform: loadProfileIfNeeded)
        .navigationTitle(title)
        .themeSecondaryView()
    }
    
    private var title: String {
        isExisting ? header.name : ""
    }
    
    private var mainView: some View {
        List {
            VPNSection(
                currentProfile: profileManager.currentProfile,
                isLoaded: isLoaded
            )
            if isLoaded {
                ProviderSection(currentProfile: profileManager.currentProfile)
                ConfigurationSection(
                    currentProfile: profileManager.currentProfile,
                    modalType: $modalType
                )
                ExtraSection(currentProfile: profileManager.currentProfile)
                DiagnosticsSection(currentProfile: profileManager.currentProfile)
                UninstallVPNSection()
            }
        }
    }
    
    private var welcomeView: some View {
        Text(L10n.Profile.Welcome.message)
            .multilineTextAlignment(.center)
            .themeInformativeText()
    }

    @ViewBuilder
    private func presentedModal(_ modalType: ModalType) -> some View {
        switch modalType {
        case .shortcuts:
            NavigationView {
                ShortcutsView(target: profileManager.currentProfile.value)
            }.themeGlobal()
            
        case .rename:
            NavigationView {
                RenameView(currentProfile: profileManager.currentProfile)
            }.themeGlobal()
            
        case .paywallShortcuts:
            NavigationView {
                PaywallView(
                    modalType: $modalType,
                    feature: .siriShortcuts
                )
            }.themeGlobal()

        case .paywallNetworkSettings:
            NavigationView {
                PaywallView(
                    modalType: $modalType,
                    feature: .networkSettings
                )
            }.themeGlobal()

        case .paywallTrustedNetworks:
            NavigationView {
                PaywallView(
                    modalType: $modalType,
                    feature: .trustedNetworks
                )
            }.themeGlobal()
        }
    }
    
    private func loadProfileIfNeeded() {
        guard !isLoaded else {
            return
        }
        guard !header.isPlaceholder else {
            pp_log.debug("ProfileView is a placeholder for WelcomeView, no active profile")
            return
        }
        do {
            let result = try profileManager.loadCurrentProfile(withId: header.id)
            if result.isReady {
                isLoaded = true
                return
            }
            Task {
                do {
                    try await profileManager.makeProfileReady(result.profile)
                    withAnimation {
                        isLoaded = true
                    }
                } catch {
                    pp_log.error("Profile \(header.id) could not be made ready: \(error)")
                    presentationMode.wrappedValue.dismiss()
                }
            }
        } catch {
            pp_log.error("Profile \(header.id) could not be loaded: \(error)")
            presentationMode.wrappedValue.dismiss()
        }
    }

    private func presentPaywallTrustedNetworks() {
        modalType = .paywallTrustedNetworks
    }
}
