//
//  GamesViewModel.swift
//  score-ios
//
//  Created by Hsia Lu wu on 12/3/24.
//

import Foundation
import SwiftUI
import GameAPI

// State enum to track the loading state
enum DataState {
    case idle        // Initial state, nothing has been fetched yet
    case loading     // Initial fetch in progress
    case refreshing     // Refreshing in progress
    case success     // Fetch completed successfully
    case error(error: ScoreError) // Fetch failed with an error message
}

class GamesViewModel: ObservableObject
{
    @Published var dataState: DataState = .idle
    @Published var games: [Game] = [] // List of all games
    @Published var allUpcomingGames: [Game] = []
    @Published var allPastGames: [Game] = []

    // private games data
    private var privateGames: [Game] = []
    private var privateUpcomingGames: [Game] = []
    private var privatePastGames: [Game] = []

    // Carousel Logic
    @Published var selectedCardIndex: Int = 0
    @Published var topUpcomingGames: [Game] = [] // Displayed in Carousel
    @Published var topPastGames: [Game] = []

    // Filters Logic
    @Published var selectedSexIndex: Int = 0
    @Published var selectedSex : Sex = .Both
    @Published var selectedSport : Sport = .All
    @Published var selectedUpcomingGames: [Game] = [] // Based on the filters
    @Published var selectedPastGames: [Game] = []
    @Published var sportSelectorOffset: CGFloat = 0

    // Singleton structure so it is shared
    static let shared = GamesViewModel()
    private init() { }

    var hasNotFetchedYet: Bool {
        return dataState == .idle
    }

    // Filtering the data
    func filter() {
        self.selectedUpcomingGames = self.allUpcomingGames.filter{ game in
            // Filter by sex
            let matchesSex = (selectedSex == .Both) || (game.sex == selectedSex)

            // Filter by sport
            let matchesSport = (selectedSport == .All) || (game.sport == selectedSport)

            // Return true if both filters are satisfied
            return matchesSex && matchesSport
        }

        self.selectedPastGames = self.allPastGames.filter{ game in
            // Filter by sex
            let matchesSex = (selectedSex == .Both) || (game.sex == selectedSex)

            // Filter by sport
            let matchesSport = (selectedSport == .All) || (game.sport == selectedSport)

            // Return true if both filters are satisfied
            return matchesSex && matchesSport
        }
    }

    @MainActor
    func loadGames() async {
        let isInitialLoad = hasNotFetchedYet
        if isInitialLoad {
            dataState = .loading
        }
        privateUpcomingGames.removeAll()
        privatePastGames.removeAll()
        do {
            var all: [GamesQuery.Data.Game] = []
            var offset = 0
            let limit = 50
            while true {
                let page = try await NetworkManager.shared.fetchGames(limit: limit, offset: offset)
                if page.isEmpty {
                    if offset == 0 {
                        dataState = .error(error: .emptyData)
                        return
                    }
                    break
                }
                all.append(contentsOf: page)
                if page.count < limit { break }
                offset += limit
            }
            processGames(all)
        } catch is CancellationError {
            // SwiftUI cancels pull-to-refresh when @Published updates rebuild the view.
            if isInitialLoad && games.isEmpty {
                dataState = .idle
            } else {
                dataState = .success
            }
        } catch {
            dataState = .error(error: .networkError)
        }
    }

    private func processGames(_ gameDataArray: [GamesQuery.Data.Game]) {
        var updatedGames: [Game] = []
        gameDataArray.indices.forEach { index in
            let gameData = gameDataArray[index]
            let game = Game(game: gameData)
            if Sport.allCases.contains(game.sport) && game.sport != Sport.All {
                // append the game only if it is upcoming/live
                let now = Date()
                let twoHours: TimeInterval = 2 * 60 * 60 // TODO: How to decide if a game is live
                let calendar = Calendar.current
                let startOfToday = calendar.startOfDay(for: now)
                let isLive = game.date < now && now.timeIntervalSince(game.date) <= twoHours
                let isUpcoming = game.date > now
                let isFinishedToday = game.date < now && game.date >= startOfToday
                let isFinishedByToday = game.date < startOfToday
                updatedGames.append(game)
                if isLive {
                    self.privateUpcomingGames.insert(game, at: 0)
                } else if isUpcoming {
                    self.privateUpcomingGames.append(game)
                } else if isFinishedToday {
                    self.privateUpcomingGames.append(game)
                }
                if isFinishedByToday {
                    self.privatePastGames.append(game)
                }
            }
        }

        // Filter out duplicates before sorting
        self.allPastGames = uniqueGames(from: self.privatePastGames)
        self.allUpcomingGames = uniqueGames(from: self.privateUpcomingGames)
        self.games = uniqueGames(from: updatedGames)

        // Sort all the collections
        self.allPastGames.sort(by: {$0.date > $1.date})
        self.allUpcomingGames.sort(by: {$0.date < $1.date})
        self.games.sort(by: {$0.date < $1.date})
        self.topUpcomingGames = Array(self.allUpcomingGames.prefix(3))
        self.topPastGames = Array(self.allPastGames.prefix(3))
        self.filter()

        // Update state to success
        self.dataState = .success
    }

    // Function to filter out duplicate games by ID
    func uniqueGames(from games: [Game]) -> [Game] {
        var uniqueGames: [Game] = []
        var seenIDs: Set<String> = []

        for game in games {
            if let id = game.serverId, !seenIDs.contains(id) {
                uniqueGames.append(game)
                seenIDs.insert(id)
            }
        }

        return uniqueGames
    }

    // Method to retry after an error
    func retryFetch () async {
        await loadGames()
    }
}

extension DataState: Equatable {
    
    static func == (lhs: DataState, rhs: DataState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case (.loading, .loading):
            return true
        case (.success, .success):
            return true
        case (.error(let lhsError), .error(let rhsError)):
            if lhsError == rhsError {
                return true
            } else {
                return false
            }
        default:
            return false
        }
    }

}
