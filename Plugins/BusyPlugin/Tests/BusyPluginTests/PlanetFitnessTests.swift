@testable import BusyPlugin
import XCTest

final class PlanetFitnessURLTests: XCTestCase {
    private let canonical = "https://www.planetfitness.com/gyms/philadelphia-washington-ave-pa"

    func testAClubLinkInAnyCommonFormIsRecognised() {
        for query in [
            "https://www.planetfitness.com/gyms/philadelphia-washington-ave-pa",
            "https://www.planetfitness.com/gyms/philadelphia-washington-ave-pa/",
            "https://planetfitness.com/gyms/philadelphia-washington-ave-pa/offers",
            "planetfitness.com/gyms/philadelphia-washington-ave-pa",
            "  www.planetfitness.com/gyms/Philadelphia-Washington-Ave-PA?utm_source=x  ",
        ] {
            XCTAssertEqual(planetFitnessClubURL(query: query)?.absoluteString, canonical, query)
        }
    }

    func testEverythingElseIsLeftToGoogle() {
        for query in [
            "Planet Fitness Washington Ave Philadelphia",
            "https://www.planetfitness.com/",
            "https://www.planetfitness.com/gyms/",
            "https://www.google.com/maps/place/Planet+Fitness",
            "https://evil.example/planetfitness.com/gyms/x",
        ] {
            XCTAssertNil(planetFitnessClubURL(query: query), query)
        }
    }
}

final class PlanetFitnessWordingTests: XCTestCase {
    /// Planet Fitness's meter is ten bars of 10% capacity; one bar means no
    /// waits, three mean lines. The wording maps onto BusyLevel's phrases.
    func testWordingFollowsTheMetersBars() {
        XCTAssertEqual(PlanetFitness.wording(percent: 0), "Not too busy")
        XCTAssertEqual(PlanetFitness.wording(percent: 10), "Not too busy")
        XCTAssertEqual(PlanetFitness.wording(percent: 11), "A little busy")
        XCTAssertEqual(PlanetFitness.wording(percent: 20), "A little busy")
        XCTAssertEqual(PlanetFitness.wording(percent: 21), "Busy")
        XCTAssertEqual(BusyLevel.from(statusText: PlanetFitness.wording(percent: 11), percent: 11), .moderate)
        XCTAssertEqual(BusyLevel.from(statusText: PlanetFitness.wording(percent: 5), percent: 5), .quiet)
        XCTAssertEqual(BusyLevel.from(statusText: PlanetFitness.wording(percent: 30), percent: 30), .busy)
    }
}

final class HeadcountDecodingTests: XCTestCase {
    private let base = #""found":true,"hasConsentForm":false,"name":"x","statusText":null,"isLive":true,"livePercent":11,"usualPercent":null,"currentHour":null,"day":1,"hours":[]"#

    func testHeadcountAndCapacityAreRead() throws {
        let page = try decodeExtractedPage("{" + base + #","headcount":38,"capacity":334}"#)
        XCTAssertEqual(page.reading.headcount, 38)
        XCTAssertEqual(page.reading.capacity, 334)
    }

    /// Google's payload never has them, and readings saved by older versions
    /// must still load.
    func testTheyAreOptional() throws {
        let page = try decodeExtractedPage("{" + base + "}")
        XCTAssertNil(page.reading.headcount)
        let old = try JSONDecoder().decode(BusyReading.self, from: Data(#"{"isLive":false,"hours":[]}"#.utf8))
        XCTAssertNil(old.capacity)
    }
}

@MainActor
final class PlanetFitnessSourceTests: XCTestCase {
    private func payload(found: Bool, percent: Int? = 11) -> LoadedPage {
        let percentJSON = percent.map(String.init) ?? "null"
        return LoadedPage(
            payload: #"{"found":\#(found),"hasConsentForm":false,"name":"Planet Fitness Philadelphia (Washington Ave)","statusText":null,"isLive":true,"livePercent":\#(percentJSON),"usualPercent":null,"currentHour":null,"day":1,"hours":[{"hour":7,"percent":16}],"headcount":38,"capacity":334}"#,
            finalURL: URL(string: "https://www.planetfitness.com/gyms/philadelphia-washington-ave-pa")
        )
    }

    func testAClubPageBecomesAReadingWithWording() throws {
        let reading = try PlanetFitnessBusynessSource.judge(payload(found: true))
        XCTAssertEqual(reading.name, "Planet Fitness Philadelphia (Washington Ave)")
        XCTAssertEqual(reading.livePercent, 11)
        XCTAssertEqual(reading.statusText, "A little busy")
        XCTAssertEqual(reading.headcount, 38)
        XCTAssertEqual(reading.level, .moderate)
    }

    func testAPageWithoutTheMeterIsReported() {
        XCTAssertThrowsError(try PlanetFitnessBusynessSource.judge(payload(found: false))) { error in
            XCTAssertEqual(error as? BusyError, .noCrowdMeter)
        }
    }
}

@MainActor
final class RoutingSourceTests: XCTestCase {
    func testClubLinksGoToPlanetFitnessAndTheRestToGoogle() async throws {
        let google = FakeBusynessSource(), planetFitness = FakeBusynessSource()
        let router = RoutingBusynessSource(google: google, planetFitness: planetFitness)
        _ = try await router.fetch(query: "planetfitness.com/gyms/philadelphia-washington-ave-pa")
        _ = try await router.fetch(query: "Lion Gym Kesavadasapuram")
        XCTAssertEqual(planetFitness.queries, ["planetfitness.com/gyms/philadelphia-washington-ave-pa"])
        XCTAssertEqual(google.queries, ["Lion Gym Kesavadasapuram"])
    }
}

@MainActor
final class StarterPlacesTests: XCTestCase {
    func testAFreshInstallStartsWithTheSampleClub() {
        let store = BusyStore(storage: BusyFixture.temporaryStorage(), source: FakeBusynessSource(),
                              starterPlaces: [PlanetFitness.sampleClub])
        XCTAssertEqual(store.places.map(\.query), [PlanetFitness.sampleClub])
    }

    /// Someone who removed every place keeps an empty list.
    func testAnExistingEmptyListIsLeftAlone() {
        let storage = BusyFixture.temporaryStorage()
        let first = BusyStore(storage: storage, source: FakeBusynessSource())
        first.saveNow()
        let second = BusyStore(storage: storage, source: FakeBusynessSource(), starterPlaces: [PlanetFitness.sampleClub])
        XCTAssertTrue(second.places.isEmpty)
    }

    func testTheSampleIsTheWashingtonAveClub() {
        XCTAssertEqual(PlanetFitness.sampleClub, "https://www.planetfitness.com/gyms/philadelphia-washington-ave-pa")
    }
}

final class HeadcountSummaryTests: XCTestCase {
    func testAHeadcountReadsAsPeopleAndPercentFull() {
        let reading = BusyReading(statusText: "A little busy", isLive: true, livePercent: 11, headcount: 38, capacity: 334)
        XCTAssertEqual(reading.summary, "A little busy · 11% full · 38 of 334 people")
    }

    func testGoogleReadingsAreUnchanged() {
        let reading = BusyReading(statusText: "Busy", isLive: true, livePercent: 90)
        XCTAssertEqual(reading.summary, "Busy · 90% now")
    }
}

final class ChartCeilingTests: XCTestCase {
    func testGoogleChartsKeepTheirHundredScale() {
        XCTAssertEqual(BusyReading(hours: [HourBusyness(hour: 9, percent: 40)]).chartCeiling, 100)
    }

    /// A gym rarely passes a fifth of capacity, so on a 0–100 scale its day
    /// would be a flat line. Head-count charts scale to the day's own peak.
    func testHeadcountChartsScaleToTheDaysPeak() {
        let reading = BusyReading(isLive: true, livePercent: 8,
                                  hours: [HourBusyness(hour: 7, percent: 16), HourBusyness(hour: 18, percent: 21)],
                                  headcount: 28, capacity: 334)
        XCTAssertEqual(reading.chartCeiling, 21)
        let liveAbovePeak = BusyReading(isLive: true, livePercent: 30, hours: [HourBusyness(hour: 7, percent: 16)], capacity: 334)
        XCTAssertEqual(liveAbovePeak.chartCeiling, 30)
        XCTAssertEqual(BusyReading(capacity: 334).chartCeiling, 1, "never divides by zero")
    }
}
