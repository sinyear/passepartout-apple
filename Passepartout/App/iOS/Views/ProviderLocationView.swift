//
//  ProviderLocationView.swift
//  Passepartout
//
//  Created by Davide De Rosa on 2/19/22.
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

struct ProviderLocationView: View {
    @ObservedObject private var appManager: AppManager
    
    @ObservedObject private var providerManager: ProviderManager

    @ObservedObject private var currentProfile: ObservableProfile
    
    private let isEditable: Bool

    private var providerName: ProviderName {
        guard let name = currentProfile.value.header.providerName else {
            assertionFailure("Not a provider")
            return ""
        }
        return name
    }
    
    private var vpnProtocol: VPNProtocolType {
        currentProfile.value.currentVPNProtocol
    }

    @Binding private var selectedServer: ProviderServer?
    
    @Binding private var favoriteLocationIds: Set<String>?
    
    @AppStorage(AppManager.DefaultKey.isShowingFavorites.rawValue) private var isShowingFavorites = false

    private var isShowingEmptyFavorites: Bool {
        guard isShowingFavorites else {
            return false
        }
        return favoriteLocationIds?.isEmpty ?? true
    }
    
    // XXX: do not escape mutating 'self', use constant providerManager
    init(currentProfile: ObservableProfile, isEditable: Bool, isPresented: Binding<Bool>) {
        let providerManager: ProviderManager = .shared

        appManager = .shared
        self.providerManager = providerManager
        self.currentProfile = currentProfile
        self.isEditable = isEditable
        
        _selectedServer = .init {
            guard let serverId = currentProfile.value.providerServerId() else {
                return nil
            }
            return providerManager.server(withId: serverId)
        } set: {
            // user never selects a nil server
            guard let server = $0 else {
                return
            }
            currentProfile.value.setProviderServer(server)
            isPresented.wrappedValue = false
        }
        _favoriteLocationIds = .init {
            currentProfile.value.providerFavoriteLocationIds()
        } set: {
            currentProfile.value.setProviderFavoriteLocationIds($0)
        }
    }
    
    var body: some View {
        debugChanges()
        return Group {
            if !isEmpty {
                mainView
            } else {
                EmptyView()
            }
        }.navigationTitle(L10n.Provider.Location.title)
        .toolbar(content: toolbar)
    }
    
    private var isEmpty: Bool {
        currentProfile.value.isPlaceholder || !currentProfile.value.isProvider
    }
    
    private var mainView: some View {
        ScrollViewReader { scrollProxy in
            List {
                if !isShowingEmptyFavorites {
                    categoriesView
                } else {
                    emptyFavoritesSection
                }
            }.onAppear {
                scrollToSelectedLocation(scrollProxy)
            }
        }
    }

    @ViewBuilder
    private func toolbar() -> some View {
        if #available(iOS 15, macOS 12, *) {
            Button {
                withAnimation {
                    isShowingFavorites.toggle()
                }
            } label: {
                themeFavoritesImage(isShowingFavorites).asSystemImage
            }
        } else {
            self
        }
    }

    private var categoriesView: some View {
        ForEach(categories, content: categorySection)
    }
    
    private func categorySection(_ category: ProviderCategory) -> some View {
        Section(
            header: !category.name.isEmpty ? Text(category.name) : nil
        ) {
            ForEach(filteredLocations(for: category)) { location in
                if isEditable, #available(iOS 15, macOS 12, *) {
                    locationRow(location)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            favoriteActions(location)
                        }
                } else {
                    locationRow(location)
                }
            }
        }
    }
    
    @ViewBuilder
    private func locationRow(_ location: ProviderLocation) -> some View {
        if let onlyServer = location.onlyServer {
            singleServerRow(location, onlyServer)
        } else {
            multipleServersRow(location)
        }
    }
    
    private func multipleServersRow(_ location: ProviderLocation) -> some View {
        NavigationLink(destination: {
            ServerListView(
                location: location,
                selectedServer: $selectedServer
            ).navigationTitle(location.localizedCountry)
        }, label: {
            LocationRow(
                location: location,
                selectedLocationId: selectedServer?.locationId
            )
        })
    }

    private func singleServerRow(_ location: ProviderLocation, _ server: ProviderServer) -> some View {
        Button {
            selectedServer = server
        } label: {
            LocationRow(
                location: location,
                selectedLocationId: selectedServer?.locationId
            )
        }
    }
    
    private var emptyFavoritesSection: some View {
        Section(
            footer: Text(L10n.Provider.Location.Sections.EmptyFavorites.footer)
        ) {
        }
    }

    @available(iOS 15, macOS 12, *)
    private func favoriteActions(_ location: ProviderLocation) -> some View {
        Button {
            withAnimation {
                toggleFavoriteLocation(location)
            }
        } label: {
            themeFavoriteActionImage(!isFavoriteLocation(location)).asSystemImage
        }.tint(themePrimaryBackgroundColor)
    }
}

extension ProviderLocationView {
    private func server(withId serverId: String) -> ProviderServer? {
        providerManager.server(withId: serverId)
    }
    
    private var categories: [ProviderCategory] {
        providerManager.categories(providerName, vpnProtocol: vpnProtocol)
            .filter {
                !filteredLocations(for: $0).isEmpty
            }.sorted()
    }

    private func filteredLocations(for category: ProviderCategory) -> [ProviderLocation] {
        let locations: [ProviderLocation]
        if isShowingFavorites {
            locations = category.locations.filter {
                favoriteLocationIds?.contains($0.id) ?? false
            }
        } else {
            locations = category.locations
        }
        return locations.sorted()
    }
    
    private func isFavoriteLocation(_ location: ProviderLocation) -> Bool {
        return favoriteLocationIds?.contains(location.id) ?? false
    }
    
    private func toggleFavoriteLocation(_ location: ProviderLocation) {
        if !isFavoriteLocation(location) {
            if favoriteLocationIds == nil {
                favoriteLocationIds = [location.id]
            } else {
                favoriteLocationIds?.insert(location.id)
            }
        } else {
            favoriteLocationIds?.remove(location.id)
        }
        // may trigger view updates?
//        pp_log.debug("New favorite locations: \(favoriteLocationIds ?? [])")
    }
}

extension ProviderLocationView {
    struct LocationRow: View {
        let location: ProviderLocation

        let selectedLocationId: String?
        
        var body: some View {
            HStack {
                themeAssetsCountryImage(location.countryCode).asAssetImage
                VStack {
                    if let singleServer = location.onlyServer, let _ = singleServer.details {
                        Text(location.localizedCountry)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(singleServer.localizedDetails.uppercased())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(location.localizedCountry)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                }.withTrailingCheckmark(when: location.id == selectedLocationId)
            }.frame(height: 60)
        }
    }

    struct ServerListView: View {
        @ObservedObject private var providerManager: ProviderManager
        
        private let location: ProviderLocation

        @Binding private var selectedServer: ProviderServer?
        
        init(location: ProviderLocation, selectedServer: Binding<ProviderServer?>) {
            providerManager = .shared
            self.location = location
            _selectedServer = selectedServer
        }

        var body: some View {
            ScrollViewReader { scrollProxy in
                List {
                    ForEach(servers) { server in
                        Button(server.localizedDetailsWithDefault) {
                            selectedServer = server
                        }.withTrailingCheckmark(when: server.id == selectedServer?.id)
                    }
                }.onAppear {
                    scrollToSelectedServer(scrollProxy)
                }
            }
        }

        private var servers: [ProviderServer] {
            return providerManager.servers(forLocation: location).sorted()
        }
    }
}

extension ProviderLocationView {
    private func scrollToSelectedLocation(_ proxy: ScrollViewProxy) {
        proxy.maybeScrollTo(selectedServer?.locationId)
    }
}

extension ProviderLocationView.ServerListView {
    private func scrollToSelectedServer(_ proxy: ScrollViewProxy) {
        proxy.maybeScrollTo(selectedServer?.id)
    }
}