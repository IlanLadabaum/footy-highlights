import FootyKit

/// Navigation stack destinations: competitions → rounds → round → player.
enum Route: Hashable {
    case competition(String)
    case round(RoundID)
    case player(MatchKey)
    /// Plays the queue from the top.
    case queue
}
