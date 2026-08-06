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

    func testEntriesResponseDecodeSample() throws {
        let json = """
        {
          "entries": [
            {
              "id": "entry-expense",
              "kind": "expense",
              "amount": 1200,
              "date": "2026-08-06",
              "yearMonth": "2026-08",
              "category": "food",
              "cardId": null,
              "incomeSource": null,
              "note": "昼食",
              "sourceRuleId": null,
              "isManuallyEdited": false
            },
            {
              "id": "entry-card",
              "kind": "card_expense",
              "amount": 3800,
              "date": "2026-08-07",
              "yearMonth": "2026-08",
              "category": "business",
              "cardId": "card-1",
              "incomeSource": null,
              "note": "ソフトウェア",
              "sourceRuleId": null,
              "isManuallyEdited": false
            },
            {
              "id": "entry-income",
              "kind": "income",
              "amount": 300000,
              "date": "2026-08-25",
              "yearMonth": "2026-08",
              "category": null,
              "cardId": null,
              "incomeSource": "salary",
              "note": "給与",
              "sourceRuleId": "rule-salary",
              "isManuallyEdited": false
            }
          ],
          "breakdown": [
            { "category": "business", "amount": 3800 },
            { "category": "food", "amount": 1200 }
          ],
          "quality": { "fixed": 15000, "variable": 5000, "savingTip": 500 }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(EntriesResponse.self, from: json)

        XCTAssertEqual(response.entries.map(\.kind), [.expense, .cardExpense, .income])
        XCTAssertEqual(response.breakdown.map(\.category), [.business, .food])
        XCTAssertEqual(response.quality.savingTip, 500)
    }

    func testCalendarResponseDecodeSample() throws {
        let json = """
        {
          "month": "2026-08",
          "today": "2026-08-06",
          "events": [
            {
              "type": "fixed_cost",
              "entryId": "entry-rent",
              "name": "家賃",
              "date": "2026-08-25",
              "amount": 90000,
              "cardId": null,
              "cardName": null,
              "category": "housing"
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
            },
            {
              "type": "salary",
              "entryId": "entry-salary",
              "name": "給与",
              "date": "2026-08-25",
              "amount": 300000
            }
          ],
          "paymentCount": 2,
          "paymentTotal": 108000
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(CalendarResponse.self, from: json)

        XCTAssertEqual(response.events.map(\.id), ["entry-rent", "card-1-2026-08-27", "entry-salary"])
        XCTAssertEqual(response.paymentCount, 2)
        XCTAssertEqual(response.paymentTotal, 108000)
    }

    func testCardDetailResponseDecodeSample() throws {
        let json = """
        {
          "card": {
            "id": "card-1",
            "name": "楽天カード",
            "closingDay": 15,
            "paymentDay": 27,
            "revolvingAmount": null,
            "creditLimit": 300000,
            "carryoverBalance": 12000,
            "archived": false,
            "utilization": 86000,
            "monthUsage": 24000,
            "nextPayment": {
              "month": "2026-09",
              "paymentDate": "2026-09-27",
              "amount": 54000,
              "closed": false
            }
          },
          "payments": [
            {
              "month": "2026-09",
              "paymentDate": "2026-09-27",
              "amount": 54000,
              "fromExclusive": "2026-07-15",
              "toInclusive": "2026-08-15",
              "closed": false,
              "balanceAfter": 32000
            }
          ],
          "recentExpenses": [
            {
              "id": "entry-card",
              "kind": "card_expense",
              "amount": 3800,
              "date": "2026-08-07",
              "yearMonth": "2026-08",
              "category": "business",
              "cardId": "card-1",
              "incomeSource": null,
              "note": "ソフトウェア",
              "sourceRuleId": null,
              "isManuallyEdited": false
            }
          ],
          "linkedRules": [
            {
              "id": "rule-1",
              "direction": "expense",
              "name": "Adobe",
              "amount": 3280,
              "dayOfMonth": 10,
              "cardId": "card-1",
              "category": "business",
              "startMonth": "2026-08",
              "active": true
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(CardDetailResponse.self, from: json)

        XCTAssertEqual(response.card.name, "楽天カード")
        XCTAssertEqual(response.card.nextPayment?.amount, 54000)
        XCTAssertEqual(response.payments.first?.balanceAfter, 32000)
        XCTAssertEqual(response.recentExpenses.first?.kind, .cardExpense)
        XCTAssertEqual(response.linkedRules.first?.category, .business)
    }

    func testTaxEstimateResponseDecodeSample() throws {
        let json = """
        {
          "year": 2026,
          "businessIncomeYtd": 1800000,
          "businessExpenseYtd": 240000,
          "profitYtd": 1560000,
          "rate": 0.2,
          "estimatedTax": 312000,
          "monthlySetAside": 39000,
          "annualProjection": 468000
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(TaxEstimateResponse.self, from: json)

        XCTAssertEqual(response.year, 2026)
        XCTAssertEqual(response.profitYtd, 1560000)
        XCTAssertEqual(response.rate, 0.2)
        XCTAssertEqual(response.monthlySetAside, 39000)
        XCTAssertEqual(response.annualProjection, 468000)
    }
}
