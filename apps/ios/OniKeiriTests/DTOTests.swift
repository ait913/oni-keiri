import XCTest
@testable import OniKeiri

final class DTOTests: XCTestCase {
    func testHomeResponseDecodeRoundTrip() throws {
        let json = """
        {
          "today": "2026-08-20",
          "month": "2026-08",
          "spendable": 137000,
          "remaining": 237000,
          "income": 300000,
          "spending": 63000,
          "cashExpense": 45000,
          "cardPaymentDue": 18000,
          "cardUsage": 8000,
          "savingsGoal": 100000,
          "dailySeries": [
            { "date": "2026-08-01", "value": 0, "projected": false },
            { "date": "2026-08-31", "value": 237000, "projected": true }
          ],
          "minPoint": { "date": "2026-08-10", "value": -18000 },
          "upcomingPayments": [
            {
              "type": "fixed_cost",
              "entryId": "entry-fixed",
              "name": "Netflix",
              "date": "2026-08-27",
              "amount": 1490,
              "cardId": null,
              "cardName": null,
              "category": "entertainment"
            },
            {
              "type": "card_payment",
              "cardId": "card-1",
              "cardName": "楽天カード",
              "date": "2026-08-27",
              "amount": 18000,
              "fromExclusive": "2026-06-15",
              "toInclusive": "2026-07-15",
              "closed": true
            }
          ],
          "upcomingTotal": 19490,
          "employmentType": "freelance"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let response = try decoder.decode(HomeResponse.self, from: json)

        XCTAssertEqual(response.today, "2026-08-20")
        XCTAssertEqual(response.spendable, 137000)
        XCTAssertEqual(response.minPoint, MinPointDto(date: "2026-08-10", value: -18000))
        XCTAssertEqual(response.upcomingPayments.map(\.id), ["entry-fixed", "card-1-2026-08-27"])

        let encoded = try JSONEncoder().encode(response)
        let roundTripped = try decoder.decode(HomeResponse.self, from: encoded)
        XCTAssertEqual(roundTripped, response)
    }
}
