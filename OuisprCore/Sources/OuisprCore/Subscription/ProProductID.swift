// OuisprCore/Sources/OuisprCore/Subscription/ProProductID.swift
// App Store Connect product identifiers for Ouispr Pro.
import Foundation

/// The App Store Connect product identifiers Ouispr Pro sells (#215).
///
/// WHY these live in OuisprCore rather than beside `SubscriptionManager`:
/// an identifier is permanent once the product exists in App Store Connect —
/// a typo cannot be renamed, only abandoned. OuisprApp has no test target, so
/// constants declared there are unverifiable; here the OuisprCore suite can
/// check them against the local StoreKit configuration the app ships with.
///
/// WHY an enum with no cases: a caseless enum can never be instantiated,
/// making it a pure namespace for static constants (common Swift pattern).
public enum ProProductID {
    /// Auto-renewable subscription, 1 month, no introductory offer.
    public static let monthly = "solutions.pivi.ouispr.pro.monthly"

    /// Auto-renewable subscription, 1 year, no introductory offer. The free trial is
    /// the app's own 14-day reverse trial (`ProTrial.durationDays`), not a StoreKit offer.
    public static let yearly = "solutions.pivi.ouispr.pro.yearly"

    /// Non-consumable one-off purchase (#54, #350).
    ///
    /// WHY it is not in the `Ouispr Pro` subscription group: a group makes its
    /// members mutually exclusive plans a user switches between, which is
    /// meaningless for a purchase that never renews. Being outside the group
    /// also means it can carry no introductory offer — free trials are a
    /// subscription feature.
    public static let lifetime = "solutions.pivi.ouispr.pro.lifetime2"

    /// Every identifier `SubscriptionManager` asks StoreKit for.
    ///
    /// WHY a Set: `Product.products(for:)` takes a collection of identifiers
    /// and its result order is unspecified, so nothing downstream may depend
    /// on the declaration order here.
    public static let all: Set<String> = [monthly, yearly, lifetime]
}
